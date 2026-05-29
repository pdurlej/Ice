//
//  CodexBarCLIQuotaBackend.swift
//  Ice
//
//  Reads provider usage by shelling out to the CodexBar CLI:
//      codexbar usage --provider <p> --json --json-only --no-color
//
//  The CLI emits a JSON array (one element per account) on stdout.
//  Shape (trimmed to what we use), verified against codexbar 0.134.0:
//
//    [{
//      "usage": {
//        "primary":   { "usedPercent": 0,  "windowMinutes": 300,   "resetsAt": "2026-05-29T15:50:37Z" },
//        "secondary": { "usedPercent": 21, "windowMinutes": 10080,  "resetsAt": "2026-06-04T15:20:16Z" },
//        "tertiary":  null,
//        "updatedAt": "2026-05-29T11:23:39Z",
//        "accountEmail": "user@example.com",
//        "loginMethod": "pro",
//        "identity": { "accountEmail": "user@example.com", "loginMethod": "pro" }
//      },
//      "source": "codex-cli",
//      "provider": "codex"
//    }]
//
//  Some providers omit resetsAt (e.g. Ollama's primary) and leftPercent
//  is never present, so we derive it as 100 - usedPercent.
//

import Foundation
import OSLog

struct CodexBarCLIQuotaBackend: AIQuotaBackend {
    /// Optional explicit path from settings; tried first when non-empty.
    let configuredPath: String?
    /// Per-invocation timeout.
    let timeout: TimeInterval

    private static let logger = Logger(category: "AIQuota.CodexBarCLI")

    init(configuredPath: String? = nil, timeout: TimeInterval = 60) {
        self.configuredPath = configuredPath
        self.timeout = timeout
    }

    // MARK: Binary resolution

    /// Candidate locations, in priority order.
    private var candidatePaths: [String] {
        var paths: [String] = []
        if let configuredPath, !configuredPath.isEmpty {
            paths.append(configuredPath)
        }
        paths.append("/opt/homebrew/bin/codexbar")
        paths.append("/usr/local/bin/codexbar")
        paths.append("/Applications/CodexBar.app/Contents/Helpers/CodexBarCLI")
        return paths
    }

    /// The first existing+executable candidate path, if any.
    var resolvedBinaryPath: String? {
        let fm = FileManager.default
        for path in candidatePaths where fm.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    var isAvailable: Bool { resolvedBinaryPath != nil }

    var unavailableReason: String? {
        isAvailable ? nil : "CodexBar CLI not found. Install CodexBar or set a custom path in AI Quotas settings."
    }

    // MARK: Fetch

    func fetch(provider: AIQuotaProvider) async -> AIQuotaSnapshot {
        guard let binary = resolvedBinaryPath else {
            return .failure(provider, unavailableReason ?? "CodexBar CLI not found")
        }

        let arguments = [
            "usage",
            "--provider", provider.rawValue,
            "--json", "--json-only", "--no-color",
        ]

        do {
            let data = try await runProcess(binary: binary, arguments: arguments)
            return Self.parse(data: data, provider: provider)
        } catch {
            Self.logger.error("CodexBar CLI failed for \(provider.rawValue, privacy: .public): \(error, privacy: .public)")
            return .failure(provider, "CLI error: \(error.localizedDescription)")
        }
    }

    // MARK: Process plumbing

    private enum ProcessError: LocalizedError {
        case timedOut
        case nonZeroExit(Int32)
        case launchFailed(String)

        var errorDescription: String? {
            switch self {
            case .timedOut: "timed out"
            case .nonZeroExit(let code): "exited with code \(code)"
            case .launchFailed(let why): "could not launch: \(why)"
            }
        }
    }

    /// Runs the CLI and returns stdout. Enforces `timeout` and never
    /// blocks the caller's thread (uses a continuation around
    /// terminationHandler plus a timeout task).
    private func runProcess(binary: String, arguments: [String]) async throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        return try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                    process.terminationHandler = { proc in
                        // Read stdout to EOF *after* the process exits, so we
                        // never resume on a partially-flushed pipe. The old
                        // readabilityHandler + snapshot path could race the
                        // final chunk and resume with empty/truncated JSON →
                        // a spurious "?" in the menu bar. codexbar's output is
                        // a few KB, well under the 64KB pipe buffer, so reading
                        // post-exit cannot deadlock.
                        let out = stdout.fileHandleForReading.readDataToEndOfFile()
                        _ = stderr.fileHandleForReading.readDataToEndOfFile()  // drain
                        if proc.terminationStatus == 0 {
                            continuation.resume(returning: out)
                        } else {
                            continuation.resume(throwing: ProcessError.nonZeroExit(proc.terminationStatus))
                        }
                    }
                    do {
                        try process.run()
                    } catch {
                        continuation.resume(throwing: ProcessError.launchFailed(error.localizedDescription))
                    }
                }
            }
            group.addTask { [timeout] in
                try await Task.sleep(for: .seconds(timeout))
                throw ProcessError.timedOut
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else {
                throw ProcessError.timedOut
            }
            // If the timeout won, kill the still-running process.
            if process.isRunning {
                process.terminate()
            }
            return result
        }
    }

    // MARK: Parsing (pure, unit-testable)

    /// Parses CodexBar CLI JSON (object or array) into a snapshot.
    /// Pure function: no I/O, so tests can feed it fixtures.
    static func parse(data rawData: Data, provider: AIQuotaProvider) -> AIQuotaSnapshot {
        // Defensive: trim any non-JSON noise before the first top-level
        // opener. Status lines like "[codex notify] …" belong on stderr
        // (which we drop), but if one ever lands on stdout this keeps the
        // decode from failing.
        let data = Self.jsonSlice(of: rawData)
        guard !data.isEmpty else {
            return .failure(provider, "empty CLI output")
        }

        let decoder = JSONDecoder()
        let response: CLIResponse?

        // Accept either a top-level array (the normal case) or a bare
        // object (defensive).
        if let array = try? decoder.decode([CLIResponse].self, from: data) {
            // Prefer the element whose provider matches; else the first.
            response = array.first(where: { $0.provider == provider.rawValue }) ?? array.first
        } else if let single = try? decoder.decode(CLIResponse.self, from: data) {
            response = single
        } else {
            // Surface a short, redacted prefix to help debugging without
            // dumping the whole payload (which may carry account emails).
            let prefix = String(data: data.prefix(80), encoding: .utf8) ?? "<binary>"
            return .failure(provider, "could not parse CLI JSON (starts: \(prefix))")
        }

        guard let response, let usage = response.usage else {
            return .failure(provider, "no usage data from CLI")
        }

        let extraWindows = (usage.extraRateWindows ?? []).map { extra in
            AIQuotaExtraWindow(
                id: extra.id ?? extra.title ?? "?",
                title: extra.title ?? extra.id ?? "?",
                usedPercent: extra.window?.usedPercent
            )
        }

        return AIQuotaSnapshot(
            provider: provider,
            source: response.source,
            updatedAt: Self.parseDate(usage.updatedAt),
            primary: usage.primary.map { $0.toWindow(kind: .primary) },
            secondary: usage.secondary.map { $0.toWindow(kind: .secondary) },
            tertiary: usage.tertiary.map { $0.toWindow(kind: .tertiary) },
            extraWindows: extraWindows,
            account: usage.accountEmail ?? usage.identity?.accountEmail,
            plan: usage.loginMethod ?? usage.identity?.loginMethod,
            error: nil
        )
    }

    /// Returns the data starting at the first byte that actually begins
    /// JSON: a '[' or '{' whose next non-whitespace byte is JSON-structural
    /// (so a log line such as "[codex notify] …", where '[' is followed by a
    /// letter, is skipped). Returns the input unchanged if none is found.
    static func jsonSlice(of data: Data) -> Data {
        let bytes = [UInt8](data)
        func isWS(_ b: UInt8) -> Bool { b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D }
        func looksLikeJSONStart(after i: Int) -> Bool {
            var j = i + 1
            while j < bytes.count, isWS(bytes[j]) { j += 1 }
            guard j < bytes.count else { return false }
            let b = bytes[j]
            return b == UInt8(ascii: "{") || b == UInt8(ascii: "[")
                || b == UInt8(ascii: "\"") || b == UInt8(ascii: "}") || b == UInt8(ascii: "]")
                || (b >= UInt8(ascii: "0") && b <= UInt8(ascii: "9")) || b == UInt8(ascii: "-")
                || b == UInt8(ascii: "t") || b == UInt8(ascii: "f") || b == UInt8(ascii: "n")
        }
        for i in bytes.indices {
            let b = bytes[i]
            let isOpener = b == UInt8(ascii: "[") || b == UInt8(ascii: "{")
            if isOpener, looksLikeJSONStart(after: i) {
                return Data(bytes[i...])
            }
        }
        return data
    }

    private static let isoFormatter = ISO8601DateFormatter()

    static func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        return isoFormatter.date(from: string)
    }

    // MARK: CLI JSON decode types

    private struct CLIResponse: Decodable {
        let usage: CLIUsage?
        let source: String?
        let provider: String?
    }

    private struct CLIUsage: Decodable {
        let primary: CLIWindow?
        let secondary: CLIWindow?
        let tertiary: CLIWindow?
        let updatedAt: String?
        let accountEmail: String?
        let loginMethod: String?
        let identity: CLIIdentity?
        let extraRateWindows: [CLIExtraWindow]?
    }

    private struct CLIIdentity: Decodable {
        let accountEmail: String?
        let loginMethod: String?
    }

    /// One entry of Antigravity's `extraRateWindows` (per-model usage).
    private struct CLIExtraWindow: Decodable {
        let id: String?
        let title: String?
        let window: CLIWindow?
    }

    private struct CLIWindow: Decodable {
        let usedPercent: Double?
        let leftPercent: Double?
        let windowMinutes: Int?
        let resetsAt: String?

        func toWindow(kind: AIQuotaWindow.Kind) -> AIQuotaWindow {
            let derivedLeft = leftPercent ?? usedPercent.map { 100 - $0 }
            return AIQuotaWindow(
                kind: kind,
                usedPercent: usedPercent,
                leftPercent: derivedLeft,
                windowMinutes: windowMinutes,
                resetsAt: CodexBarCLIQuotaBackend.parseDate(resetsAt)
            )
        }
    }
}
