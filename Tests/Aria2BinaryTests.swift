import Foundation

// swiftc Sources/Models.swift Sources/Aria2Binary.swift Tests/Aria2BinaryTests.swift -o /tmp/tricklebar-binary-tests
@main
struct Aria2BinaryTests {
    static func main() throws {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: directory) }

        let legacy = try JSONDecoder().decode(TrickleBarConfig.self, from: Data(#"{"port":1234,"secret":"test"}"#.utf8))
        precondition(legacy.aria2cPath == nil, "Old config should use automatic discovery")
        var config = legacy
        config.aria2cPath = directory.appendingPathComponent("custom aria2c").path
        let restored = try JSONDecoder().decode(TrickleBarConfig.self, from: JSONEncoder().encode(config))
        precondition(restored.aria2cPath == config.aria2cPath, "Custom path must survive relaunch")
        precondition(Aria2Binary.resolve(customPath: config.aria2cPath) == config.aria2cPath,
                     "An explicit missing path must not silently fall back")

        let cases: [(String, String, Bool, String?, Aria2Binary.BinaryError?)] = [
            ("custom aria2c", "#!/bin/sh\n[ \"$1\" = \"--version\" ] || exit 2\nprintf 'aria2 version 1.37.0\\nCopyright test\\n'\n",
             true, "1.37.0", nil),
            ("wrong-program", "#!/bin/sh\nprintf 'another program 1.0\\n'\n",
             true, nil, .unreadableVersion),
            ("failed-version", "#!/bin/sh\nprintf 'aria2 version 1.37.0\\n'\nexit 1\n",
             true, nil, .unreadableVersion),
            ("empty-version", "#!/bin/sh\nprintf 'aria2 version \\n'\n",
             true, nil, .unreadableVersion),
            ("not-executable", "#!/bin/sh\nprintf 'aria2 version 1.37.0\\n'\n",
             false, nil, .notExecutable),
            ("unresponsive", "#!/bin/sh\nexec /bin/sleep 10\n",
             true, nil, .timedOut),
        ]
        for (name, script, executable, expectedVersion, expectedError) in cases {
            let url = directory.appendingPathComponent(name)
            try script.write(to: url, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: executable ? 0o700 : 0o600], ofItemAtPath: url.path)
            let start = Date()
            do {
                let version = try Aria2Binary.version(at: url.path)
                precondition(expectedError == nil && version == expectedVersion, "Unexpected version for \(name)")
            } catch let error as Aria2Binary.BinaryError {
                precondition(error == expectedError, "Unexpected error for \(name): \(error)")
            }
            precondition(Date().timeIntervalSince(start) < 5, "Version check must not hang")
        }
        for path in [directory.path, directory.appendingPathComponent("missing").path] {
            do {
                _ = try Aria2Binary.version(at: path)
                preconditionFailure("Directories and missing files must be rejected")
            } catch let error as Aria2Binary.BinaryError {
                precondition(error == .notExecutable)
            }
        }
        if let detected = Aria2Binary.resolve(customPath: nil) {
            print("Detected \(detected), version \(try Aria2Binary.version(at: detected))")
        }
        print("Passed binary validation, timeout, discovery, and config compatibility checks.")
    }
}
