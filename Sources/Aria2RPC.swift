import Foundation

final class Aria2RPC {
    let port: Int
    let secret: String
    private let baseURL: URL
    private let session: URLSession

    init(port: Int, secret: String) {
        self.port = port
        self.secret = secret
        self.baseURL = URL(string: "http://127.0.0.1:\(port)/jsonrpc")!
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 5
        cfg.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: cfg)
    }

    // MARK: - Core call

    func call(method: String, params: [Any], completion: @escaping (Any?, Error?) -> Void) {
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": "1",
            "method": method,
            "params": ["token:\(secret)"] + params,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else {
            completion(nil, RPCError.serialization)
            return
        }
        var req = URLRequest(url: baseURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        session.dataTask(with: req) { data, _, error in
            if let error { completion(nil, error); return }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { completion(nil, RPCError.parseError); return }
            if let rpcErr = json["error"] as? [String: Any] {
                let msg = rpcErr["message"] as? String ?? "RPC error"
                completion(nil, RPCError.rpcError(msg))
                return
            }
            completion(json["result"], nil)
        }.resume()
    }

    @discardableResult
    func callSync(method: String, params: [Any]) throws -> Any? {
        var result: Any?
        var callError: Error?
        let sem = DispatchSemaphore(value: 0)
        call(method: method, params: params) { r, e in
            result = r; callError = e; sem.signal()
        }
        sem.wait()
        if let callError { throw callError }
        return result
    }

    // MARK: - Download keys requested on every poll

    private let dlKeys: [String] = [
        "gid", "status", "totalLength", "completedLength", "downloadSpeed",
        "dir", "files", "errorCode", "errorMessage", "bittorrent",
    ]

    // MARK: - Methods

    func getVersion(completion: @escaping (Bool) -> Void) {
        call(method: "aria2.getVersion", params: []) { r, e in
            completion(e == nil && r != nil)
        }
    }

    func addUri(urls: [String], options: [String: Any] = [:], completion: @escaping (String?, Error?) -> Void) {
        call(method: "aria2.addUri", params: [urls, options]) { r, e in
            completion(r as? String, e)
        }
    }

    func addUriSync(urls: [String], options: [String: Any] = [:]) throws -> String {
        guard let gid = try callSync(method: "aria2.addUri", params: [urls, options]) as? String else {
            throw RPCError.unexpectedResult
        }
        return gid
    }

    func tellActive(completion: @escaping ([Download], Error?) -> Void) {
        call(method: "aria2.tellActive", params: [dlKeys]) { r, e in
            completion(Self.parseDownloads(r), e)
        }
    }

    func tellWaiting(offset: Int = 0, num: Int = 50, completion: @escaping ([Download], Error?) -> Void) {
        call(method: "aria2.tellWaiting", params: [offset, num, dlKeys]) { r, e in
            completion(Self.parseDownloads(r), e)
        }
    }

    func tellStopped(offset: Int = 0, num: Int = 200, completion: @escaping ([Download], Error?) -> Void) {
        call(method: "aria2.tellStopped", params: [offset, num, dlKeys]) { r, e in
            completion(Self.parseDownloads(r), e)
        }
    }

    func pause(gid: String, completion: @escaping (Error?) -> Void) {
        call(method: "aria2.pause", params: [gid]) { _, e in completion(e) }
    }

    func unpause(gid: String, completion: @escaping (Error?) -> Void) {
        call(method: "aria2.unpause", params: [gid]) { _, e in completion(e) }
    }

    func remove(gid: String, completion: @escaping (Error?) -> Void) {
        call(method: "aria2.remove", params: [gid]) { _, e in
            if e != nil {
                self.call(method: "aria2.forceRemove", params: [gid]) { _, e2 in completion(e2) }
            } else {
                completion(nil)
            }
        }
    }

    func removeResult(gid: String, completion: @escaping (Error?) -> Void) {
        call(method: "aria2.removeDownloadResult", params: [gid]) { _, e in completion(e) }
    }

    func changeGlobalOption(_ opts: [String: Any], completion: @escaping (Error?) -> Void) {
        call(method: "aria2.changeGlobalOption", params: [opts]) { _, e in completion(e) }
    }

    func saveSession(completion: @escaping (Error?) -> Void) {
        call(method: "aria2.saveSession", params: []) { _, e in completion(e) }
    }

    func saveSessionSync() {
        _ = try? callSync(method: "aria2.saveSession", params: [])
    }

    // MARK: - Parsing

    private static func parseDownloads(_ raw: Any?) -> [Download] {
        guard let arr = raw as? [[String: Any]] else { return [] }
        return arr.compactMap { Download(rpc: $0) }
    }
}

extension Download {
    init?(rpc d: [String: Any]) {
        guard let gid = d["gid"] as? String,
              let statusStr = d["status"] as? String,
              let status = DownloadStatus(rawValue: statusStr)
        else { return nil }

        self.gid = gid
        self.status = status
        self.totalLength = Int64(d["totalLength"] as? String ?? "0") ?? 0
        self.completedLength = Int64(d["completedLength"] as? String ?? "0") ?? 0
        self.downloadSpeed = Int64(d["downloadSpeed"] as? String ?? "0") ?? 0
        self.dir = d["dir"] as? String ?? ""
        self.errorCode = d["errorCode"] as? String
        self.errorMessage = d["errorMessage"] as? String

        if let bt = d["bittorrent"] as? [String: Any],
           let info = bt["info"] as? [String: Any] {
            self.torrentName = info["name"] as? String
        } else {
            self.torrentName = nil
        }

        if let rawFiles = d["files"] as? [[String: Any]] {
            self.files = rawFiles.map { f in
                let uriObjs = f["uris"] as? [[String: Any]] ?? []
                let uris = uriObjs.compactMap { $0["uri"] as? String }
                return DownloadFile(
                    path: f["path"] as? String ?? "",
                    length: Int64(f["length"] as? String ?? "0") ?? 0,
                    completedLength: Int64(f["completedLength"] as? String ?? "0") ?? 0,
                    uris: uris
                )
            }
        } else {
            self.files = []
        }
    }
}

enum RPCError: LocalizedError {
    case serialization, parseError, unexpectedResult, noConfig
    case rpcError(String)

    var errorDescription: String? {
        switch self {
        case .serialization: return "Failed to serialize request"
        case .parseError: return "Failed to parse response"
        case .unexpectedResult: return "Unexpected result type"
        case .noConfig: return "No daemon config found — launch TrickleBar.app first"
        case .rpcError(let m): return m
        }
    }
}
