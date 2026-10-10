import Foundation
import Darwin

enum Aria2Binary {
    // An explicit choice takes precedence, including when it has gone missing.
    static func resolve(customPath: String?) -> String? {
        if let customPath, !customPath.isEmpty {
            return (customPath as NSString).expandingTildeInPath
        }
        let candidates = [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/aria2c").path,
            "/opt/homebrew/bin/aria2c",
            "/usr/local/bin/aria2c",
            "/usr/bin/aria2c",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) { return path }
        for directory in (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":") {
            let path = URL(fileURLWithPath: String(directory)).appendingPathComponent("aria2c").path
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    // Run off the main thread. A timeout keeps a bad selection from hanging Settings.
    static func version(at path: String) throws -> String {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              !isDirectory.boolValue, FileManager.default.isExecutableFile(atPath: path) else {
            throw BinaryError.notExecutable
        }
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        guard FileManager.default.createFile(atPath: outputURL.path, contents: nil) else {
            throw BinaryError.unreadableVersion
        }
        defer { try? FileManager.default.removeItem(at: outputURL) }
        let output = try FileHandle(forUpdating: outputURL)
        defer { try? output.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        try process.run()
        if finished.wait(timeout: .now() + 3) == .timedOut {
            if process.isRunning { process.terminate() }
            if finished.wait(timeout: .now() + 0.5) == .timedOut, process.isRunning {
                Darwin.kill(process.processIdentifier, SIGKILL)
            }
            process.waitUntilExit()
            throw BinaryError.timedOut
        }
        try output.seek(toOffset: 0)
        let data = try output.read(upToCount: 4096) ?? Data()
        let firstLine = String(data: data, encoding: .utf8)?.components(separatedBy: .newlines).first ?? ""
        let prefix = "aria2 version "
        guard process.terminationStatus == 0, firstLine.hasPrefix(prefix) else {
            throw BinaryError.unreadableVersion
        }
        let version = String(firstLine.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        guard !version.isEmpty else { throw BinaryError.unreadableVersion }
        return version
    }

    enum BinaryError: LocalizedError {
        case notExecutable, unreadableVersion, timedOut

        var errorDescription: String? {
            switch self {
            case .notExecutable: return "Choose an executable aria2c file."
            case .unreadableVersion: return "This file did not report an aria2c version."
            case .timedOut: return "The binary did not respond to --version within 3 seconds."
            }
        }
    }
}
