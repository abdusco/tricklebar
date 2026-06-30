import Foundation

enum DownloadStatus: String {
    case active, waiting, paused, complete, error, removed
}

struct DownloadFile {
    let path: String
    let length: Int64
    let completedLength: Int64
    let uris: [String]
}

struct Download {
    let gid: String
    let status: DownloadStatus
    let totalLength: Int64
    let completedLength: Int64
    let downloadSpeed: Int64
    let dir: String
    let files: [DownloadFile]
    let errorCode: String?
    let errorMessage: String?
    let torrentName: String?

    var progress: Double {
        guard totalLength > 0 else { return 0 }
        return Double(completedLength) / Double(totalLength)
    }

    var displayName: String {
        if let name = torrentName, !name.isEmpty { return name }
        if let file = files.first, !file.path.isEmpty {
            return URL(fileURLWithPath: file.path).lastPathComponent
        }
        if let name = uriFilename { return name }
        return gid
    }

    // Derive a filename from the source URL when aria2 hasn't opened the file yet
    // (e.g. downloads restored paused from a session report an empty file path).
    private var uriFilename: String? {
        guard let uri = primaryURI, let comps = URLComponents(string: uri) else { return nil }
        let last = (comps.path as NSString).lastPathComponent
        let decoded = last.removingPercentEncoding ?? last
        return decoded.isEmpty ? nil : decoded
    }

    var primaryFilePath: String? {
        guard let path = files.first?.path, !path.isEmpty else { return nil }
        return path
    }

    var primaryURI: String? {
        files.first?.uris.first
    }
}

struct DlwatchConfig: Codable {
    var port: Int
    var secret: String
}

func formatBytes(_ bytes: Int64) -> String {
    let units = ["B", "KB", "MB", "GB", "TB"]
    var value = Double(bytes)
    var idx = 0
    while value >= 1024 && idx < units.count - 1 {
        value /= 1024
        idx += 1
    }
    if idx == 0 { return "\(Int(value)) B" }
    return String(format: "%.1f %@", value, units[idx])
}
