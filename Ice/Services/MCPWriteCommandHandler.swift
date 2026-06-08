//
//  MCPWriteCommandHandler.swift
//  Ice
//
//  Ice-main-app side of the MCP write bridge. Polls for write commands
//  that MCPBackend.xpc drops into the shared file channel
//  (`MCPWriteChannel`) and executes them with Ice's own
//  `MenuBarItemManager.move` — the exact code path the Layout editor
//  uses, which can reach collapsed (off-screen) sections because Ice
//  owns the real control-item MenuBarItem objects.
//
//  MCPBackend cannot do this itself: the hidden / alwaysHidden divider
//  control items are parked off-screen when collapsed and aren't
//  enumerable from an XPC service, and expanding a section is a
//  main-app-only operation.
//

import Combine
import Foundation
import OSLog

@MainActor
final class MCPWriteCommandHandler {
    private weak var appState: AppState?
    private let logger = Logger(category: "MCPWriteCommandHandler")

    /// The id of the last command we processed, so we don't re-run it on
    /// every poll tick.
    private var lastProcessedID: String?

    /// True while a consent prompt is on screen, so concurrent poll ticks
    /// don't stack a second modal alert.
    private var authorizationInFlight = false

    private var cancellable: AnyCancellable?

    /// The single serialized mutation authority. fire.10 routes every menu-bar
    /// mutation (MCP writes, triggers, UI) through one coordinator so they
    /// never interleave; this handler no longer touches `itemManager.move`.
    private let mutationCoordinator = MenuBarMutationCoordinator()

    /// Performs setup: starts polling the shared command file.
    func performSetup(with appState: AppState) {
        self.appState = appState
        mutationCoordinator.performSetup(with: appState)

        // Cross-process change notifications on files are possible via
        // DispatchSource, but a coarse poll is simpler and plenty
        // responsive for interactive AI-driven moves. 200ms keeps a
        // move feeling immediate without busy-spinning.
        cancellable = Timer.publish(every: 0.2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.poll()
            }
        logger.debug("MCP write command handler active")
    }

    private func poll() {
        // Don't pick up new commands (or stack a second modal) while a
        // consent prompt is already on screen.
        guard !authorizationInFlight else { return }
        guard let command = MCPWriteChannel.readCommand() else { return }
        guard command.id != lastProcessedID else { return }
        logger.log("MCP write command received: \(command.id, privacy: .public)")

        // Ignore poison/stale commands left by a crashed MCPBackend.
        let age = Date().timeIntervalSince1970 - command.createdAt
        guard age <= MCPWriteChannel.staleAfter else {
            lastProcessedID = command.id
            return
        }

        lastProcessedID = command.id
        authorizationInFlight = true

        Task {
            defer { authorizationInFlight = false }

            // fire.9.8 confused-deputy stopgap: the TCC-bearing main app
            // authorizes every write in its own UI before using its
            // Accessibility power. The file channel is only a request
            // queue, never the authorization boundary.
            guard MCPWriteAuthorization.shared.authorize(command) else {
                let denied = MCPWriteChannel.Result(
                    id: command.id, success: false,
                    message: "Denied: this menu bar change was not approved in Fire.",
                    completedAt: Date().timeIntervalSince1970
                )
                try? MCPWriteChannel.writeResult(denied)
                return
            }

            logger.log(
                "Executing MCP write command \(command.id, privacy: .public): \(command.op, privacy: .public) \(command.bundleID, privacy: .public) -> \(command.toSection, privacy: .public)"
            )
            let result = await execute(command)
            do {
                try MCPWriteChannel.writeResult(result)
            } catch {
                logger.error("Failed to write MCP result: \(error, privacy: .public)")
            }
        }
    }

    /// Translates a write command into a coordinator job. Only "move" is
    /// supported. The actual mutation runs through `MenuBarMutationCoordinator`
    /// (FIFO, serialized); this handler only parses, authorizes, and replies.
    private func execute(_ command: MCPWriteChannel.Command) async -> MCPWriteChannel.Result {
        func result(_ success: Bool, _ message: String?) -> MCPWriteChannel.Result {
            MCPWriteChannel.Result(
                id: command.id, success: success, message: message,
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
