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

        // Read pipes on background queues to avoid a deadlock when the
        // child writes more than a pipe buffer's worth before exit.
        let stdoutData = LockedData()
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
            } else {
                stdoutData.append(chunk)
            }
        }
        // Drain stderr so the child never blocks on a full stderr pipe.
        stderr.fileHandleForReading.readabilityHandler = { handle in
            if handle.availableData.isEmpty { handle.readabilityHandler = nil }
        }

        return try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    process.terminationHandler = { proc in
                        // Give the readability handler a beat to flush.
                        let status = proc.terminationStatus
                        if status == 0 {
                            continuation.resume(returning: stdoutData.snapshot())
                        } else {
                            continuation.resume(throwing: ProcessError.nonZeroExit(status))
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

    /// Thread-safe accumulator for piped stdout chunks.
    private final class LockedData: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        func append(_ chunk: Data) {
            lock.lock(); defer { lock.unlock() }
            data.append(chunk)
        }
        func snapshot() -> Data {
            lock.lock(); defer { lock.unlock() }
            return data
        }
    }

    // MARK: Parsing (pure, unit-testable)

    /// Parses CodexBar CLI JSON (object or array) into a snapshot.
    /// Pure function: no I/O, so tests can feed it fixtures.
    static func parse(data: Data, provider: AIQuotaProvider) -> AIQuotaSnapshot {
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

        return AIQuotaSnapshot(
            provider: provider,
            source: response.source,
            updatedAt: Self.parseDate(usage.updatedAt),
            primary: usage.primary.map { $0.toWindow(kind: .primary) },
            secondary: usage.secondary.map { $0.toWindow(kind: .secondary) },
            account: usage.accountEmail ?? usage.identity?.accountEmail,
            plan: usage.loginMethod ?? usage.identity?.loginMethod,
            error: nil
        )
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
        let updatedAt: String?
        let accountEmail: String?
        let loginMethod: String?
        let identity: CLIIdentity?
    }

    private struct CLIIdentity: Decodable {
        let accountEmail: String?
        let loginMethod: String?
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
