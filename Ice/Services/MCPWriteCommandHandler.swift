//
//  MCPWriteCommandHandler.swift
//  Ice
//
//  Fulfiller for agent-initiated menu-bar WRITE commands (relayed from
//  MCPBackend.xpc by `MCPRelayPump` since fire.10.2; a polled file channel
//  before that). Executes them with Ice's own `MenuBarItemManager.move`
//  via the mutation coordinator — the exact code path the Layout editor
//  uses, which can reach collapsed (off-screen) sections because Ice owns
//  the real control-item MenuBarItem objects.
//
//  MCPBackend cannot do this itself: the hidden / alwaysHidden divider
//  control items are parked off-screen when collapsed and aren't
//  enumerable from an XPC service, and expanding a section is a
//  main-app-only operation.
//

import Foundation
import OSLog

@MainActor
final class MCPWriteCommandHandler {
    private weak var appState: AppState?
    private let logger = Logger(category: "MCPWriteCommandHandler")

    /// The single serialized mutation authority. fire.10 routes every menu-bar
    /// mutation (MCP writes, triggers, UI) through one coordinator so they
    /// never interleave; this handler never touches `itemManager.move`.
    private let mutationCoordinator = MenuBarMutationCoordinator.shared

    func performSetup(with appState: AppState) {
        self.appState = appState
        mutationCoordinator.performSetup(with: appState)
        logger.debug("MCP write command handler active (relay fulfiller)")
    }

    /// Fulfills one relayed write command end-to-end: staleness check →
    /// consent → serialized execution → result. Called by `MCPRelayPump`,
    /// which processes one item at a time, so consent prompts never stack.
    func fulfill(_ command: MCPWriteChannel.Command) async -> MCPWriteChannel.Result {
        logger.log("MCP write command received: \(command.id, privacy: .public)")

        func failure(_ message: String) -> MCPWriteChannel.Result {
            MCPWriteChannel.Result(
                id: command.id,
                success: false,
                message: message,
                completedAt: Date().timeIntervalSince1970
            )
        }

        // Refuse items that sat queued past their shelf life (e.g. across a
        // sleep/wake) — the requesting bridge call has long timed out.
        // Checked BEFORE the prompt, so a slow human approval still executes.
        let age = Date().timeIntervalSince1970 - command.createdAt
        guard age <= MCPWriteChannel.staleAfter else {
            logger.notice("Dropping stale write command \(command.id, privacy: .public) (age \(age, format: .fixed(precision: 1))s)")
            return failure("Command expired before Fire could process it.")
        }

        // The bundle id is shown verbatim in the consent prompt; reject anything
        // outside the reverse-DNS charset so it can't smuggle bidi/zero-width
        // text into what the user is approving.
        guard AgentInput.validBundleID(command.bundleID) != nil else {
            return failure("Invalid bundle id.")
        }

        // fire.9.8 confused-deputy gate: the TCC-bearing main app authorizes
        // every write in its own UI before using its Accessibility power.
        // Since fire.10.2 the relay underneath is authenticated (same-team
        // XPC), making this prompt defense-in-depth rather than the only
        // boundary — it stays regardless.
        guard MCPWriteAuthorization.shared.authorize(command) else {
            return failure("Denied: this menu bar change was not approved in Fire.")
        }

        logger.log(
            "Executing MCP write command \(command.id, privacy: .public): \(command.op, privacy: .public) \(command.bundleID, privacy: .public) -> \(command.toSection, privacy: .public)"
        )
        return await execute(command)
    }

    /// Translates a write command into a coordinator job. Only "move" is
    /// supported. The actual mutation runs through `MenuBarMutationCoordinator`
    /// (FIFO, serialized); this handler only parses, authorizes, and replies.
    private func execute(_ command: MCPWriteChannel.Command) async -> MCPWriteChannel.Result {
        func result(_ success: Bool, _ message: String?) -> MCPWriteChannel.Result {
            MCPWriteChannel.Result(
                id: command.id,
                success: success,
                message: message,
                completedAt: Date().timeIntervalSince1970
            )
        }

        guard command.op == "move" else {
            return result(false, "Unknown op '\(command.op)'")
        }
        guard let section = TriggerSection(rawValue: command.toSection) else {
            return result(false, "Unknown section '\(command.toSection)'")
        }

        let job = MutationJob(
            source: .mcp,
            moves: [MovePlan(bundleID: command.bundleID, toSection: section)]
        )
        let outcome = await mutationCoordinator.enqueue(job)
        return result(
            outcome.success,
            outcome.success ? "Moved \(command.bundleID) to \(command.toSection)" : outcome.message
        )
    }
}
