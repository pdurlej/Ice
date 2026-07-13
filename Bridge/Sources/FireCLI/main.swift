import Foundation

private enum CLIError: LocalizedError {
    case usage(String)
    case bridgeNotFound
    case bridgeClosed
    case invalidResponse
    case remote(String)

    var errorDescription: String? {
        switch self {
        case .usage(let message), .remote(let message): message
        case .bridgeNotFound:
            "IceMCPBridge was not found. Run the embedded CLI from Ice.app or set FIRE_MCP_BRIDGE."
        case .bridgeClosed:
            "IceMCPBridge closed before replying. Is Fire running?"
        case .invalidResponse:
            "IceMCPBridge returned an invalid JSON-RPC response."
        }
    }
}

private final class LineReader {
    private let handle: FileHandle
    private var buffer = Data()

    init(_ handle: FileHandle) { self.handle = handle }

    func next() throws -> Data {
        while true {
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[..<newline]
                buffer.removeSubrange(...newline)
                if !line.isEmpty { return Data(line) }
            }
            let chunk = handle.availableData
            guard !chunk.isEmpty else { throw CLIError.bridgeClosed }
            buffer.append(chunk)
        }
    }
}

private final class MCPClient {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let reader: LineReader
    private var nextID = 1

    init(bridge: URL) throws {
        reader = LineReader(output.fileHandleForReading)
        process.executableURL = bridge
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.standardError
        try process.run()
    }

    deinit {
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
    }

    func initialize() throws {
        _ = try request(
            method: "initialize",
            params: [
                "protocolVersion": "2025-03-26",
                "capabilities": [:],
                "clientInfo": ["name": "fire-cli", "version": "1.0.0"],
            ]
        )
        try notify(method: "notifications/initialized", params: [:])
    }

    func request(method: String, params: [String: Any] = [:]) throws -> [String: Any] {
        let id = nextID
        nextID += 1
        try write(["jsonrpc": "2.0", "id": id, "method": method, "params": params])

        while true {
            let data = try reader.next()
            guard let message = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CLIError.invalidResponse
            }
            guard (message["id"] as? Int) == id else { continue }
            if let error = message["error"] as? [String: Any] {
                throw CLIError.remote(error["message"] as? String ?? "Unknown JSON-RPC error")
            }
            guard let result = message["result"] as? [String: Any] else {
                throw CLIError.invalidResponse
            }
            return result
        }
    }

    func notify(method: String, params: [String: Any]) throws {
        try write(["jsonrpc": "2.0", "method": method, "params": params])
    }

    private func write(_ object: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try input.fileHandleForWriting.write(contentsOf: data)
    }
}

private func bridgeURL() throws -> URL {
    let environment = ProcessInfo.processInfo.environment
    let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    let candidates = [
        environment["FIRE_MCP_BRIDGE"].map { URL(fileURLWithPath: $0) },
        executable.deletingLastPathComponent().appendingPathComponent("IceMCPBridge"),
        URL(fileURLWithPath: "/Applications/Ice.app/Contents/MacOS/IceMCPBridge"),
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Bridge/.build/debug/IceMCPBridge"),
    ].compactMap { $0 }

    guard let url = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
        throw CLIError.bridgeNotFound
    }
    return url
}

private func parseObject(_ raw: String) throws -> [String: Any] {
    guard
        let data = raw.data(using: .utf8),
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
        throw CLIError.usage("Arguments must be a JSON object.")
    }
    return object
}

private func toolResult(_ result: [String: Any]) throws -> String {
    if let isError = result["isError"] as? Bool, isError {
        let message = (result["content"] as? [[String: Any]])?
            .compactMap { $0["text"] as? String }
            .joined(separator: "\n") ?? "MCP tool failed"
        throw CLIError.remote(message)
    }
    let text = (result["content"] as? [[String: Any]])?
        .compactMap { $0["text"] as? String }
        .joined(separator: "\n")
    if let text, !text.isEmpty { return text }
    let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
    return String(decoding: data, as: UTF8.self)
}

private func printJSON(_ object: Any) throws {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: data, as: UTF8.self))
}

private let help = """
Fire CLI — local control plane for Fire From Ice

Usage:
  fire doctor
  fire capabilities
  fire items [alwaysVisible|hidden|alwaysHidden]
  fire contexts
  fire call <tool> [json-object]

Writes use Fire's normal approval and sealed-capability path. `fire call` does
not bypass consent; use `fire items` first and prefer exact selectors.
"""

private func run() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard let command = arguments.first else { throw CLIError.usage(help) }
    if command == "help" || command == "--help" || command == "-h" {
        print(help)
        return
    }

    let bridge = try bridgeURL()
    let client = try MCPClient(bridge: bridge)
    try client.initialize()

    switch command {
    case "doctor":
        let tools = try client.request(method: "tools/list")
        let itemResult = try client.request(
            method: "tools/call",
            params: ["name": "list_items", "arguments": [:]]
        )
        _ = try toolResult(itemResult)
        let count = (tools["tools"] as? [Any])?.count ?? 0
        print("Fire is ready: MCP initialized, \(count) tools available, menu bar readable.")

    case "capabilities":
        try printJSON(try client.request(method: "tools/list"))

    case "items":
        guard arguments.count <= 2 else { throw CLIError.usage(help) }
        let params: [String: Any]
        if let section = arguments.dropFirst().first {
            let allowed = ["alwaysVisible", "hidden", "alwaysHidden"]
            guard allowed.contains(section) else {
                throw CLIError.usage("Unknown section \(section). Expected: \(allowed.joined(separator: ", ")).")
            }
            params = ["section": section]
        } else {
            params = [:]
        }
        let result = try client.request(
            method: "tools/call",
            params: ["name": "list_items", "arguments": params]
        )
        print(try toolResult(result))

    case "contexts":
        let result = try client.request(
            method: "tools/call",
            params: ["name": "list_contexts", "arguments": [:]]
        )
        print(try toolResult(result))

    case "call":
        guard arguments.count >= 2, arguments.count <= 3 else { throw CLIError.usage(help) }
        let tool = arguments[1]
        let params = try arguments.count == 3 ? parseObject(arguments[2]) : [:]
        let result = try client.request(
            method: "tools/call",
            params: ["name": tool, "arguments": params]
        )
        print(try toolResult(result))

    default:
        throw CLIError.usage("Unknown command \(command).\n\n\(help)")
    }
}

do {
    try run()
} catch {
    FileHandle.standardError.write(Data("fire: \(error.localizedDescription)\n".utf8))
    exit(error is CLIError ? 2 : 1)
}
