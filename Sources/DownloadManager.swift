import Foundation
import Darwin

final class DownloadManager {
    private(set) var downloads: [Download] = []
    private(set) var config: DlwatchConfig?
    var onUpdate: (() -> Void)?

    private var rpc: Aria2RPC?
    private var aria2cProcess: Process?
    private var pollTimer: Timer?

    static let configDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/dlwatch")
    static let configFile = configDir.appendingPathComponent("config")
    static let dataDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/share/dlwatch")
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
    private func loadOrCreateConfig() -> DlwatchConfig {
        if let data = try? Data(contentsOf: DownloadManager.configFile),
           let cfg = try? JSONDecoder().decode(DlwatchConfig.self, from: data) {
            return cfg
        }
        let cfg = DlwatchConfig(port: findFreePort(), secret: UUID().uuidString.replacingOccurrences(of: "-", with: ""))
        if let data = try? JSONEncoder().encode(cfg) {
            try? data.write(to: DownloadManager.configFile)
        }
        return cfg
    }

    private func saveConfig(_ cfg: DlwatchConfig) {
        if let data = try? JSONEncoder().encode(cfg) {
            try? data.write(to: DownloadManager.configFile)
        }
    }

    // Read existing config — used by CLI path
    static func readConfig() -> DlwatchConfig? {
        guard let data = try? Data(contentsOf: configFile),
              let cfg = try? JSONDecoder().decode(DlwatchConfig.self, from: data)
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

    private func launchAria2c(_ cfg: DlwatchConfig, completion: @escaping () -> Void) {
        guard let aria2cPath = findAria2cBinary() else {
            fputs("dlwatch: aria2c not found — install it via 'brew install aria2'\n", stderr)
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
            fputs("dlwatch: failed to launch aria2c: \(error)\n", stderr)
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
        pollOnce()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.pollOnce()
        }
    }

    private func pollOnce() {
        guard let rpc else { return }
        var active: [Download] = []
        var waiting: [Download] = []
        var stopped: [Download] = []
        let group = DispatchGroup()

        group.enter()
        rpc.tellActive { d, _ in active = d; group.leave() }

        group.enter()
        rpc.tellWaiting { d, _ in waiting = d; group.leave() }

        group.enter()
        rpc.tellStopped { d, _ in stopped = d; group.leave() }

        group.notify(queue: .main) { [weak self] in
            self?.downloads = active + waiting + stopped
            self?.onUpdate?()
        }
    }

    // MARK: - Actions

    func addDownload(urls: [String], options: [String: Any] = [:], completion: @escaping (String?, Error?) -> Void) {
        rpc?.addUri(urls: urls, options: options) { [weak self] gid, err in
            self?.persistSession()
            completion(gid, err)
        }
    }

    func pause(gid: String) { rpc?.pause(gid: gid) { [weak self] _ in self?.persistSession() } }
    func resume(gid: String) { rpc?.unpause(gid: gid) { [weak self] _ in self?.persistSession() } }
    func cancel(gid: String) { rpc?.remove(gid: gid) { [weak self] _ in self?.persistSession() } }
    func removeResult(gid: String) { rpc?.removeResult(gid: gid) { [weak self] _ in self?.persistSession() } }

    func clearCompleted() {
        for dl in downloads where dl.status == .complete {
            removeResult(gid: dl.gid)
        }
    }

    // Flush the session so the on-disk state reflects the latest action.
    private func persistSession() { rpc?.saveSession { _ in } }

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
        rpc.removeResult(gid: download.gid) { _ in
            let opts: [String: Any] = ["dir": download.dir]
            rpc.addUri(urls: [uri], options: opts) { _, _ in }
        }
    }
}
