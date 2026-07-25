import Foundation

enum CLIHandler {
    static func shouldRunAsCLI() -> Bool {
        let args = CommandLine.arguments.dropFirst()
        if args.contains("-h") || args.contains("--help") { return true }
        if args.contains("-v") || args.contains("--version") { return true }
        return args.contains { a in
            a.hasPrefix("http://") || a.hasPrefix("https://") ||
            a.hasPrefix("ftp://")  || a.hasPrefix("magnet:")  ||
            a == "-i" || a == "--input-file" ||
            a.hasPrefix("--input-file=") || a == "-Z" || a == "--force-sequential"
        }
    }

    static func run() {
        let args = Array(CommandLine.arguments.dropFirst())

        if args.contains("-h") || args.contains("--help") { printHelp(); return }
        if args.contains("-v") || args.contains("--version") { print("tricklebar 1.0.0"); return }

        guard let cfg = DownloadManager.readConfig() else {
            fputs("tricklebar: no running daemon — open TrickleBar.app first\n", stderr)
            exit(1)
        }

        let rpc = Aria2RPC(port: cfg.port, secret: cfg.secret)

        var urls: [String] = []
        var options: [String: Any] = [:]
        var headers: [String] = []
        var globalOptions: [String: Any] = [:]
        var inputFile: String?

        var i = 0
        while i < args.count {
            let arg = args[i]
            func next() -> String? { i += 1; return i < args.count ? args[i] : nil }

            switch arg {
            case "-h", "--help":    break
            case "-v", "--version": break
            case "-d":  if let v = next() { options["dir"] = v }
            case "-o":  if let v = next() { options["out"] = v }
            case "-s":  if let v = next() { options["split"] = v }
            case "-x":  if let v = next() { options["max-connection-per-server"] = v }
            case "-k":  if let v = next() { options["min-split-size"] = v }
            case "-c", "--continue": options["continue"] = "true"
            case "-U":  if let v = next() { options["user-agent"] = v }
            case "-i":  if let v = next() { inputFile = v }
            case "-j":  if let v = next() { globalOptions["max-concurrent-downloads"] = v }
            case "-Z", "--force-sequential": break
            case "--pause": options["pause"] = "true"
            default:
                if let v = strip(arg, "--dir=")                        { options["dir"] = v }
                else if let v = strip(arg, "--out=")                   { options["out"] = v }
                else if let v = strip(arg, "--split=")                 { options["split"] = v }
                else if let v = strip(arg, "--max-connection-per-server=") { options["max-connection-per-server"] = v }
                else if let v = strip(arg, "--min-split-size=")        { options["min-split-size"] = v }
                else if let v = strip(arg, "--referer=")               { options["referer"] = v }
                else if let v = strip(arg, "--user-agent=")            { options["user-agent"] = v }
                else if let v = strip(arg, "--header=")                { headers.append(v) }
                else if let v = strip(arg, "--http-user=")             { options["http-user"] = v }
                else if let v = strip(arg, "--http-passwd=")           { options["http-passwd"] = v }
                else if let v = strip(arg, "--all-proxy=")             { options["all-proxy"] = v }
                else if let v = strip(arg, "--all-proxy-user=")        { options["all-proxy-user"] = v }
                else if let v = strip(arg, "--all-proxy-passwd=")      { options["all-proxy-passwd"] = v }
                else if let v = strip(arg, "--max-download-limit=")    { options["max-download-limit"] = v }
                else if let v = strip(arg, "--max-upload-limit=")      { options["max-upload-limit"] = v }
                else if let v = strip(arg, "--input-file=")            { inputFile = v }
                else if let v = strip(arg, "--max-concurrent-downloads=") { globalOptions["max-concurrent-downloads"] = v }
                else if arg.hasPrefix("http://") || arg.hasPrefix("https://") ||
                        arg.hasPrefix("ftp://")  || arg.hasPrefix("magnet:")   { urls.append(arg) }
                else if !arg.hasPrefix("-") { urls.append(arg) }
                else { fputs("tricklebar: unknown option '\(arg)' (ignored)\n", stderr) }
            }
            i += 1
        }

        if !headers.isEmpty { options["header"] = headers }

        if let f = inputFile {
            let path = (f as NSString).expandingTildeInPath
            if let content = try? String(contentsOfFile: path, encoding: .utf8) {
                let lines = content.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty && !$0.hasPrefix("#") }
                urls.append(contentsOf: lines)
            } else {
                fputs("tricklebar: cannot read input file '\(f)'\n", stderr)
            }
        }

        guard !urls.isEmpty else {
            fputs("tricklebar: no URLs provided\n", stderr)
            fputs("Usage: tricklebar [options] URL...\n", stderr)
            fputs("       tricklebar --help\n", stderr)
            exit(1)
        }

        if !globalOptions.isEmpty {
            _ = try? rpc.callSync(method: "aria2.changeGlobalOption", params: [globalOptions])
        }

        var exitCode: Int32 = 0
        for url in urls {
            do {
                let gid = try rpc.addUriSync(urls: [url], options: options)
                print(gid)
            } catch {
                fputs("tricklebar: failed to add \(url): \(error.localizedDescription)\n", stderr)
                exitCode = 1
            }
        }
        exit(exitCode)
    }

    private static func strip(_ s: String, _ prefix: String) -> String? {
        guard s.hasPrefix(prefix) else { return nil }
        return String(s.dropFirst(prefix.count))
    }

    private static func printHelp() {
        print("""
        tricklebar — aria2c-compatible download manager

        Usage:
          tricklebar [options] URL...     Add download(s) to running daemon
          tricklebar -i FILE              Read URLs from file
          open TrickleBar.app             Launch menu bar interface

        Options (subset of aria2c flags):
          -d, --dir=DIR                Download directory
          -o, --out=FILE               Output filename
          -s, --split=N                Connections per download
          -x, --max-connection-per-server=N
          -k, --min-split-size=SIZE    e.g. 1M, 5M
          -c, --continue               Continue partial download
          -j, --max-concurrent-downloads=N
          -U, --user-agent=UA
              --referer=URL
              --header=HEADER          Repeatable
              --http-user=USER
              --http-passwd=PASSWD
              --all-proxy=PROXY        e.g. http://proxy:8080
              --max-download-limit=N   e.g. 500K, 2M
              --max-upload-limit=N
          -i, --input-file=FILE        One URL per line
          -Z, --force-sequential       (accepted, always sequential)
              --pause                  Add download in paused state
          -h, --help
          -v, --version
        """)
    }
}
