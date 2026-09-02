import Foundation
import Darwin

final class DownloadManager {
    private(set) var downloads: [Download] = []
    private(set) var config: TrickleBarConfig?
    var onUpdate: (() -> Void)?

    private var rpc: Aria2RPC?
    private var aria2cProcess: Process?
    private var pollTimer: Timer?
    private var pollInFlight = false
    private var pollGeneration = 0
    private var stoppedPollRequested = true
    private var lastStoppedPollAt = Date.distantPast

    // GIDs with a pending on_done script (from tricklebar://add-download?...&on_done=).
    // Popped once the script has been launched so it only ever runs once per download.
    // In-memory fast path for the common case (this instance called addDownload itself);
    // entries a *different* app instance registers (see registerOnDoneScript) arrive via
    // onDoneFile instead, since that instance has no access to this in-memory dict.
    private var onDoneScripts: [String: String] = [:]
    private var lastOnDoneFileMTime = Date.distantPast
    // Called on the main thread with (download display name, combined stdout+stderr)
    // when an on_done script exits non-zero.
    var onScriptFailure: ((String, String) -> Void)?

    private static let stoppedPollInterval: TimeInterval = 15

    static let configDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/tricklebar")
    static let configFile = configDir.appendingPathComponent("config")
    static let dataDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/share/tricklebar")
    static let onDoneFile = dataDir.appendingPathComponent("on_done.json")
    static let sessionFile = dataDir.appendingPathComponent("session.txt")
    static let logFile = dataDir.appendingPathComponent("aria2c.log")

    // MARK: - GUI start

    func start() {
        createDirs()
        let cfg = loadOrCreateConfig()
        self.config = cfg
        let rpc = Aria2RPC(port: cfg.port, secret: cfg.secret)
        self.rpc = rpc

        rpc.getVersion { [weak self] alive in
            if alive {
                DispatchQueue.main.async { self?.startPolling() }
            } else {
                self?.launchAria2c(cfg) {
                    DispatchQueue.main.async { self?.startPolling() }
                }
            }
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        pollGeneration += 1
        pollInFlight = false
        // Flush the session deterministically before SIGTERM so the latest
        // paused/queued state is captured even on a quick quit.
        rpc?.saveSessionSync()
        aria2cProcess?.terminate()
        aria2cProcess = nil
    }

    // MARK: - Config

    private func createDirs() {
        let fm = FileManager.default
        try? fm.createDirectory(at: DownloadManager.configDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: DownloadManager.dataDir, withIntermediateDirectories: true)
    }

    @discardableResult
    private func loadOrCreateConfig() -> TrickleBarConfig {
        if let data = try? Data(contentsOf: DownloadManager.configFile),
           let cfg = try? JSONDecoder().decode(TrickleBarConfig.self, from: data) {
            return cfg
        }
        let cfg = TrickleBarConfig(port: findFreePort(), secret: UUID().uuidString.replacingOccurrences(of: "-", with: ""))
        if let data = try? JSONEncoder().encode(cfg) {
            try? data.write(to: DownloadManager.configFile)
        }
        return cfg
    }

    private func saveConfig(_ cfg: TrickleBarConfig) {
        if let data = try? JSONEncoder().encode(cfg) {
            try? data.write(to: DownloadManager.configFile)
        }
    }

    // Read existing config — used by CLI path
    static func readConfig() -> TrickleBarConfig? {
        guard let data = try? Data(contentsOf: configFile),
              let cfg = try? JSONDecoder().decode(TrickleBarConfig.self, from: data)
        else { return nil }
        return cfg
    }

    // MARK: - Free port via OS assignment

    private func findFreePort() -> Int {
        let sock = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return 49876 }
        defer { Darwin.close(sock) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = INADDR_ANY
        addr.sin_port = 0

        let bound = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { return 49876 }

        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(sock, $0, &len)
            }
        }
        return Int(UInt16(bigEndian: addr.sin_port))
    }

    // MARK: - aria2c process

    private func launchAria2c(_ cfg: TrickleBarConfig, completion: @escaping () -> Void) {
        guard let aria2cPath = findAria2cBinary() else {
            fputs("tricklebar: aria2c not found — install it via 'brew install aria2'\n", stderr)
            return
        }
        var args = [
            "--enable-rpc=true",
            "--rpc-listen-all=false",
            "--rpc-listen-port=\(cfg.port)",
            "--rpc-secret=\(cfg.secret)",
            "--continue=true",
            "--dir=\(cfg.resolvedDownloadDir)",
            "--save-session=\(DownloadManager.sessionFile.path)",
            "--save-session-interval=30",
            "--log=\(DownloadManager.logFile.path)",
            "--log-level=info",
            "--file-allocation=none",
            "--auto-file-renaming=true",
            "--max-concurrent-downloads=\(cfg.resolvedMaxConcurrent)",
        ]
        if FileManager.default.fileExists(atPath: DownloadManager.sessionFile.path) {
            args.append("--input-file=\(DownloadManager.sessionFile.path)")
        }
        // Custom options go last so, for any duplicate key, aria2c honors the user's
        // value over the app default (later command-line occurrence wins).
        args.append(contentsOf: cfg.customOptionArgs)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: aria2cPath)
        proc.arguments = args
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
            aria2cProcess = proc
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.2) { completion() }
        } catch {
            fputs("tricklebar: failed to launch aria2c: \(error)\n", stderr)
        }
    }

    private func findAria2cBinary() -> String? {
        let candidates = [
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/bin/aria2c").path,
            "/opt/homebrew/bin/aria2c",
            "/usr/local/bin/aria2c",
            "/usr/bin/aria2c",
        ]
        for p in candidates where FileManager.default.isExecutableFile(atPath: p) { return p }

        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        which.arguments = ["aria2c"]
        let pipe = Pipe()
        which.standardOutput = pipe
        which.standardError = FileHandle.nullDevice
        try? which.run()
        which.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return out.isEmpty ? nil : out
    }

    // MARK: - Polling

    private func startPolling() {
        pollGeneration += 1
        pollInFlight = false
        stoppedPollRequested = true
        pollOnce()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.pollOnce()
        }
    }

    private func pollOnce() {
        guard let rpc, !pollInFlight else { return }
        pollInFlight = true
        let generation = pollGeneration
        var active = downloads.filter { $0.status == .active }
        var waiting = downloads.filter { $0.status == .waiting || $0.status == .paused }
        var stopped = downloads.filter {
            $0.status == .complete || $0.status == .error || $0.status == .removed
        }
        let previousActiveGIDs = Set(active.map(\.gid))
        let shouldPollStopped = stoppedPollRequested
            || Date().timeIntervalSince(lastStoppedPollAt) >= Self.stoppedPollInterval
        if shouldPollStopped { stoppedPollRequested = false }
        var activeSucceeded = false
        var waitingSucceeded = false
        var stoppedSucceeded = false
        let group = DispatchGroup()

        group.enter()
        rpc.tellActive { d, error in
            if error == nil { active = d; activeSucceeded = true }
            group.leave()
        }

        group.enter()
        rpc.tellWaiting { d, error in
            if error == nil { waiting = d; waitingSucceeded = true }
            group.leave()
        }

        if shouldPollStopped {
            group.enter()
            rpc.tellStopped { d, error in
                if error == nil { stopped = d; stoppedSucceeded = true }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self, self.pollGeneration == generation, self.rpc === rpc else { return }
            self.pollInFlight = false
            if stoppedSucceeded {
                self.lastStoppedPollAt = Date()
            } else if shouldPollStopped {
                self.stoppedPollRequested = true
            }
            guard activeSucceeded || waitingSucceeded || stoppedSucceeded else { return }

            let successfulGIDs = Set(
                (activeSucceeded ? active : []).map(\.gid)
                + (waitingSucceeded ? waiting : []).map(\.gid)
                + (stoppedSucceeded ? stopped : []).map(\.gid)
            )
            if !activeSucceeded { active.removeAll { successfulGIDs.contains($0.gid) } }
            if !waitingSucceeded { waiting.removeAll { successfulGIDs.contains($0.gid) } }
            if !stoppedSucceeded { stopped.removeAll { successfulGIDs.contains($0.gid) } }

            let currentGIDs = Set(active.map(\.gid) + stopped.map(\.gid))
            let needsTransitionRefresh = activeSucceeded
                && !previousActiveGIDs.subtracting(currentGIDs).isEmpty
            if needsTransitionRefresh { self.stoppedPollRequested = true }

            var seenGIDs = Set<String>()
            self.downloads = (active + waiting + stopped).reversed().filter {
                seenGIDs.insert($0.gid).inserted
            }.reversed()
            self.runDueOnDoneScripts()
            self.onUpdate?()
            if needsTransitionRefresh && !shouldPollStopped { self.pollOnce() }
        }
    }

    // MARK: - on_done scripts

    // Registers gid -> script for a download added by a *different* app instance
    // (the short-lived duplicate launched to forward a tricklebar:// URL — see
    // AppDelegate's single-instance handling). That instance has no access to the
    // owning instance's in-memory onDoneScripts, so it hands the mapping off on disk.
    static func registerOnDoneScript(gid: String, script: String) {
        try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        withOnDoneFileLock { map in map[gid] = script }
    }

    @discardableResult
    private static func withOnDoneFileLock<T>(_ body: (inout [String: String]) -> T) -> T {
        let fd = open(onDoneFile.path, O_RDWR | O_CREAT, 0o600)
        guard fd >= 0 else {
            var empty: [String: String] = [:]
            return body(&empty)
        }
        defer { close(fd) }
        flock(fd, LOCK_EX)
        defer { flock(fd, LOCK_UN) }

        let data = (try? Data(contentsOf: onDoneFile)) ?? Data()
        var map = (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
        let result = body(&map)
        if let out = try? JSONEncoder().encode(map) {
            try? out.write(to: onDoneFile, options: .atomic)
        }
        return result
    }

    // Cheap on every poll (a stat call); only pays for a locked read+write of
    // onDoneFile when its mtime moved, i.e. another instance actually wrote to it.
    private func absorbExternalOnDoneEntries() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: Self.onDoneFile.path),
              let mtime = attrs[.modificationDate] as? Date,
              mtime > lastOnDoneFileMTime
        else { return }

        let drained = Self.withOnDoneFileLock { map -> [String: String] in
            let copy = map
            map.removeAll()
            return copy
        }
        for (gid, script) in drained where onDoneScripts[gid] == nil {
            onDoneScripts[gid] = script
        }
        // Re-stat: our own clearing write just bumped mtime again.
        let attrsAfter = try? FileManager.default.attributesOfItem(atPath: Self.onDoneFile.path)
        lastOnDoneFileMTime = (attrsAfter?[.modificationDate] as? Date) ?? Date()
    }

    private func runDueOnDoneScripts() {
        absorbExternalOnDoneEntries()
        guard !onDoneScripts.isEmpty else { return }
        for dl in downloads where dl.status == .complete || dl.status == .error {
            guard let script = onDoneScripts.removeValue(forKey: dl.gid) else { continue }
            runOnDoneScript(script, for: dl)
        }
    }

    private func runOnDoneScript(_ path: String, for download: Download) {
        let expandedPath = (path as NSString).expandingTildeInPath
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: expandedPath)
        proc.arguments = [download.status.rawValue, download.primaryFilePath ?? "", download.gid, download.primaryURI ?? ""]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        do {
            try proc.run()
        } catch {
            let message = "Failed to launch on_done script '\(path)': \(error.localizedDescription)"
            DispatchQueue.main.async { [weak self] in self?.onScriptFailure?(download.displayName, message) }
            return
        }

        DispatchQueue.global().async { [weak self] in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            guard proc.terminationStatus != 0 else { return }
            let output = String(data: data, encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                self?.onScriptFailure?(download.displayName, output.isEmpty ? "(no output)" : output)
            }
        }
    }

    // MARK: - Actions

    func addDownload(urls: [String], options: [String: Any] = [:], onDone: String? = nil, completion: @escaping (String?, Error?) -> Void) {
        rpc?.addUri(urls: urls, options: options) { [weak self] gid, err in
            if let gid, let onDone { self?.onDoneScripts[gid] = onDone }
            self?.persistSession()
            completion(gid, err)
        }
    }

    func pause(gid: String) { rpc?.pause(gid: gid) { [weak self] _ in self?.persistSession() } }
    func resume(gid: String) { rpc?.unpause(gid: gid) { [weak self] _ in self?.persistSession() } }
    func cancel(gid: String) {
        rpc?.remove(gid: gid) { [weak self] error in
            self?.persistSession()
            if error == nil { self?.requestStoppedPoll() }
        }
    }

    func removeResult(gid: String) {
        rpc?.removeResult(gid: gid) { [weak self] error in
            self?.persistSession()
            if error == nil { self?.requestStoppedPoll() }
        }
    }

    func clearCompleted() {
        for dl in downloads where dl.status == .complete {
            removeResult(gid: dl.gid)
        }
    }

    // Flush the session so the on-disk state reflects the latest action.
    private func persistSession() { rpc?.saveSession { _ in } }

    private func requestStoppedPoll() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.stoppedPollRequested = true
            self.pollOnce()
        }
    }

    // MARK: - Settings

    // Persist edited settings and apply them: dir + max-concurrent take effect
    // instantly via changeGlobalOption; custom options are command-line args, so the
    // daemon is relaunched when they change (downloads resume via session + --continue).
    func applySettings(downloadDir: String?, maxConcurrent: Int, customOptions: String?) {
        let previousCustom = config?.customOptions ?? ""
        var cfg = config ?? loadOrCreateConfig()
        cfg.downloadDir = downloadDir
        cfg.maxConcurrentDownloads = maxConcurrent
        cfg.customOptions = customOptions
        saveConfig(cfg)
        config = cfg

        rpc?.changeGlobalOption([
            "dir": cfg.resolvedDownloadDir,
            "max-concurrent-downloads": String(cfg.resolvedMaxConcurrent),
        ]) { _ in }

        if (customOptions ?? "") != previousCustom {
            restartDaemon()
        }
    }

    private func restartDaemon() {
        guard let cfg = config else { return }
        pollTimer?.invalidate()
        pollTimer = nil
        pollGeneration += 1
        pollInFlight = false
        rpc?.saveSessionSync()
        aria2cProcess?.terminate()
        aria2cProcess = nil
        // Give the port a moment to free up before relaunching with the new args.
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.launchAria2c(cfg) {
                DispatchQueue.main.async { self?.startPolling() }
            }
        }
    }

    func retry(download: Download) {
        guard let rpc, let uri = download.primaryURI else {
            removeResult(gid: download.gid)
            return
        }
        rpc.removeResult(gid: download.gid) { [weak self] _ in
            self?.requestStoppedPoll()
            let opts: [String: Any] = ["dir": download.dir]
            rpc.addUri(urls: [uri], options: opts) { _, _ in }
        }
    }
}
