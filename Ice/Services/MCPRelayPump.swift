//
//  MCPRelayPump.swift
//  Ice
//
//  The main app's side of the authenticated MCP relay (fire.10.2).
//
//  Every 200ms (off the main thread) the pump asks MCPBackend.xpc for the
//  next queued agent request (`.relayFetch`), fulfills it through the
//  matching handler — consent prompt included — and posts the result back
//  (`.relayComplete`). This replaced the fire.8.2 file channels:
//
//  - AUTHENTICATED: the XPCSession is peer-gated to the same team on signed
//    builds, so no same-user process can inject commands or forge results.
//    The consent prompts become defense-in-depth instead of the only
//    boundary.
//  - NO FILE IO: the old 5 Hz file poll did a synchronous stat that caused
//    real App Hangs under disk pressure (Sentry FIRE-E). XPC round trips
//    are microseconds and never touch the disk.
//  - NO RACES: requests queue FIFO in MCPBackend's RelayQueue with
//    per-request replies — the single-slot overwrite race is gone.
//  - STRICTLY SERIAL: the pump processes one item at a time, so a write
//    consent prompt and a trigger consent prompt can never stack.
//
//  Keeping a session open means launchd keeps MCPBackend.xpc resident —
//  a few MB for instant agent responses; it also self-heals (the next
//  fetch relaunches the service if it died).
//

import Combine
import Foundation
import OSLog

@available(macOS 26.0, *)
@MainActor
final class MCPRelayPump {
    static let shared = MCPRelayPump()

    private weak var appState: AppState?
    private var cancellable: AnyCancellable?

    /// True from fetch through complete — one work item at a time.
    private var busy = false

    private let logger = Logger(category: "MCPRelayPump")
    private let client = RelayXPCClient(serviceName: "com.jordanbaird.Ice.MCPBackend")

    /// All blocking XPC calls happen here, never on the main thread.
    private static let xpcQueue = DispatchQueue(
        label: "com.jordanbaird.Ice.MCPRelayPump.xpc",
        qos: .utility
    )

    private init() {}

    func performSetup(with appState: AppState) {
        self.appState = appState

        // The pre-10.2 file channels are gone; clear any leftover files so a
        // stale command from an old build can't sit around looking meaningful.
        Self.xpcQueue.async { Self.removeLegacyChannelFiles() }

        cancellable = Timer.publish(every: 0.2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
        logger.debug("MCP relay pump active")
    }

    private func tick() {
        guard !busy else { return }
        busy = true
        // One Task for the whole fetch→fulfill→complete cycle, with `busy`
        // reset in a `defer` so it ALWAYS clears — even if a hop is dropped or
        // a fulfiller path returns early. The previous nested-async structure
        // could leave `busy == true` forever (a permanently wedged relay) if
        // any inner closure didn't run. The blocking XPC calls still happen off
        // the main thread via the awaited helpers below.
        Task { @MainActor in
            defer { busy = false }
            guard let work = await fetchWorkOffMain() else { return }
            let result = await fulfill(work)
            await postResultOffMain(result)
        }
    }

    /// Runs the blocking `relayFetch` XPC round trip off the main thread.
    private func fetchWorkOffMain() async -> MenuBarItemService.RelayWork? {
        let client = self.client
        let logger = self.logger
        return await withCheckedContinuation { continuation in
            Self.xpcQueue.async {
                continuation.resume(returning: client.fetchWork(logger: logger))
            }
        }
    }

    /// Runs the blocking `relayComplete` XPC round trip off the main thread.
    private func postResultOffMain(_ result: MenuBarItemService.RelayResult) async {
        let client = self.client
        let logger = self.logger
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            Self.xpcQueue.async {
                client.complete(result, logger: logger)
                continuation.resume()
            }
        }
    }

    /// Routes one fetched work item to its fulfiller. Runs on the main actor;
    /// consent prompts and the mutation coordinator live there.
    private func fulfill(_ work: MenuBarItemService.RelayWork) async -> MenuBarItemService.RelayResult {
        // Defense-in-depth (fire.10.4). MCPBackend.xpc is the authoritative
        // kill-switch, but the TCC-bearing main app re-checks before using its
        // Accessibility power: it refuses writes when the user has the server
        // or write toggle off, closing the window where a toggle flips between
        // the agent's request reaching the queue and Ice pulling it. Relayed
        // reads (list_triggers) are not gated here — only state changes.
        if work.isAgentWrite, let reason = Self.writeDenialReason() {
            logger.notice("Refusing relayed write — \(reason, privacy: .public)")
            return Self.deniedResult(for: work, reason: reason)
        }

        switch work {
        case .move(let command):
            guard let appState else {
                return Self.deniedResult(for: work, reason: "Ice app state unavailable")
            }
            let result = await appState.mcpWriteCommandHandler.fulfill(command)
            if result.success {
                notifyWriteIfEnabled(command)
            }
            return .move(result)

        case .trigger(let proposal):
            guard let appState else {
                return Self.deniedResult(for: work, reason: "Ice app state unavailable")
            }
            return .trigger(appState.mcpTriggerCommandHandler.fulfill(proposal))
        }
    }

    /// The live write policy, mirroring MCPBackend's authoritative gate so the
    /// two never disagree. A write needs both the server enabled AND writes
    /// allowed; returns a user-facing refusal reason, or `nil` to proceed.
    private static func writeDenialReason() -> String? {
        guard Defaults.bool(forKey: .mcpServerEnabled) else {
            return "Fire's MCP server is turned off."
        }
        guard Defaults.bool(forKey: .mcpAllowWrites) else {
            return "Fire is not allowing write operations."
        }
        return nil
    }

    /// Builds the correctly-typed failure result for a refused work item.
    private static func deniedResult(
        for work: MenuBarItemService.RelayWork,
        reason: String
    ) -> MenuBarItemService.RelayResult {
        switch work {
        case .move(let command):
            return .move(MCPWriteChannel.Result(
                id: command.id, success: false, message: reason,
                completedAt: Date().timeIntervalSince1970
            ))
        case .trigger(let proposal):
            return .trigger(MCPTriggerChannel.Result(
                id: proposal.id, success: false, triggerID: nil, enabled: false,
                triggers: nil, message: reason,
                completedAt: Date().timeIntervalSince1970
            ))
        }
    }

    /// Posts a single coalescing notification after a successful agent move,
    /// when "Notify on write operations" is on. The stable `.mcpWrite`
    /// identifier means a burst (e.g. apply_layout) updates one banner rather
    /// than stacking many.
    private func notifyWriteIfEnabled(_ command: MCPWriteChannel.Command) {
        guard Defaults.bool(forKey: .mcpNotifyOnWrite), let appState else { return }
        let placement: String
        switch MenuBarItemService.ItemSection(rawValue: command.toSection) {
        case .alwaysVisible: placement = "always visible"
        case .hidden: placement = "hidden"
        case .alwaysHidden: placement = "always hidden"
        case nil: placement = command.toSection
        }
        appState.userNotificationManager.addRequest(
            with: .mcpWrite,
            title: "Fire",
            body: "Moved \(command.bundleID) → \(placement)"
        )
    }

    /// Best-effort removal of the pre-10.2 file-channel artifacts. Touches only
    /// `FileManager` (no actor state), so it's `nonisolated` — it runs on
    /// `xpcQueue`, and inheriting `MainActor` isolation here was a warning.
    private nonisolated static func removeLegacyChannelFiles() {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support")
        let directory = base
            .appendingPathComponent("com.jordanbaird.Ice", isDirectory: true)
            .appendingPathComponent("mcp", isDirectory: true)
        let legacyFiles = [
            "write-command.json", "write-result.json",
            "trigger-proposal.json", "trigger-result.json",
        ]
        for name in legacyFiles {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }
}

// MARK: - XPC client

/// Thin synchronous client for the relay messages. Mirrors the
/// session-recreation pattern of the bridge's XPCClient: lazy session,
/// same-team peer requirement when a team identifier exists (ad-hoc builds
/// would otherwise reject themselves — upstream #744/#891), dropped and
/// recreated after any wire error. All calls happen on the pump's single
/// serial queue, so the failure-state flags need no locking of their own.
@available(macOS 26.0, *)
private final class RelayXPCClient: @unchecked Sendable {
    private let serviceName: String
    private var session: XPCSession?
    private let lock = NSLock()

    /// Connection-state flag so a dead service logs once, not at 5 Hz.
    private var lastFetchFailed = false

    init(serviceName: String) {
        self.serviceName = serviceName
    }

    private func getOrCreateSession() throws -> XPCSession {
        lock.lock()
        defer { lock.unlock() }
        if let existing = session { return existing }
        let new = try XPCSession(xpcService: serviceName, options: .inactive) { [weak self] _ in
            guard let self else { return }
            self.lock.lock()
            self.session = nil
            self.lock.unlock()
        }
        if MenuBarItemService.ownTeamIdentifier() != nil {
            new.setPeerRequirement(.isFromSameTeam())
        } else {
            // Ad-hoc build: no meaningful peer primitive exists (issue #4 —
            // see MCPBackend/Listener.swift for the full research note). A
            // spoofed service could feed this pump forged work, but every
            // write still crosses the user consent prompt.
            Logger(category: "MCPRelayPump").warning(
                "SECURITY: no team identifier (ad-hoc build) — relay peer is unauthenticated."
            )
        }
        try new.activate()
        session = new
        return new
    }

    private func send(_ request: MenuBarItemService.Request) throws -> MenuBarItemService.Response {
        let session = try getOrCreateSession()
        do {
            let reply = try session.sendSync(request)
            return try reply.decode(as: MenuBarItemService.Response.self)
        } catch {
            lock.lock()
            self.session = nil
            lock.unlock()
            throw error
        }
    }

    func fetchWork(logger: Logger) -> MenuBarItemService.RelayWork? {
        do {
            let response = try send(.relayFetch)
            if lastFetchFailed {
                lastFetchFailed = false
                logger.log("Relay reconnected to MCPBackend")
            }
            guard case .relayWork(let work) = response else {
                logger.error("Unexpected relayFetch response")
                return nil
            }
            return work
        } catch {
            if !lastFetchFailed {
                lastFetchFailed = true
                logger.warning("Relay fetch failed (will keep retrying): \(error, privacy: .public)")
            }
            return nil
        }
    }

    func complete(_ result: MenuBarItemService.RelayResult, logger: Logger) {
        do {
            let response = try send(.relayComplete(result))
            guard case .relayAck = response else {
                logger.error("Unexpected relayComplete response for \(result.id, privacy: .public)")
                return
            }
        } catch {
            logger.error("Relay complete failed for \(result.id, privacy: .public): \(error, privacy: .public)")
        }
    }
}
