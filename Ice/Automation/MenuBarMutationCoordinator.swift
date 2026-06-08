//
//  MenuBarMutationCoordinator.swift
//  Ice
//
//  The single serialized authority for menu-bar mutations (fire.10 P1).
//
//  Per GPT-5.5 Pro's review: every menu-bar mutation must pass through exactly
//  ONE actor. MCP write commands, trigger actions, and Settings-UI actions all
//  enqueue typed `MutationJob`s here; none call `itemManager.move` directly.
//  Jobs drain FIFO and non-reentrantly — `@MainActor` alone is insufficient
//  because an async move's `await` can otherwise interleave other main-actor
//  work mid-transaction.
//

import Combine
import Foundation
import OSLog

@MainActor
final class MenuBarMutationCoordinator {
    private weak var appState: AppState?

    private var queue: [(job: MutationJob, completion: (MutationResult) -> Void)] = []
    private var isExecuting = false

    private let logger = Logger(category: "MenuBarMutationCoordinator")

    func performSetup(with appState: AppState) {
        self.appState = appState
    }

    /// Enqueues a job and suspends until it has executed in FIFO order. Safe to
    /// call concurrently from the MCP handler, the trigger engine, or the UI —
    /// jobs never interleave.
    func enqueue(_ job: MutationJob) async -> MutationResult {
        await withCheckedContinuation { continuation in
            queue.append((job, { continuation.resume(returning: $0) }))
            drainIfIdle()
        }
    }

    private func drainIfIdle() {
        guard !isExecuting, !queue.isEmpty else { return }
        isExecuting = true
        let next = queue.removeFirst()
        Task { @MainActor in
            let result = await execute(next.job)
            next.completion(result)
            isExecuting = false
            drainIfIdle()
        }
    }

    // MARK: Execution

    private func execute(_ job: MutationJob) async -> MutationResult {
        logger.log(
            "Executing mutation job \(job.id, privacy: .public) source=\(job.source.rawValue, privacy: .public) moves=\(job.moves.count)"
        )
        guard let appState else {
            return MutationResult(jobID: job.id, success: false, movedCount: 0, message: "Ice app state unavailable")
        }

        var moved = 0
        var firstFailure: String?
        for move in job.moves {
            let outcome = await executeMove(move, appState: appState)
            if outcome.ok {
                moved += 1
            } else if firstFailure == nil {
                firstFailure = outcome.message
            }
        }

        let success = firstFailure == nil && moved == job.moves.count
        return MutationResult(jobID: job.id, success: success, movedCount: moved, message: firstFailure)
    }

    /// Performs one move via Ice's own `MenuBarItemManager.move` — the exact
    /// path the Layout editor uses, which can reach collapsed (off-screen)
    /// sections. (Ported from the old MCPWriteCommandHandler.execute.)
    private func executeMove(_ move: MovePlan, appState: AppState) async -> (ok: Bool, message: String?) {
        guard let section = MenuBarSection.Name(triggerSection: move.toSection) else {
            return (false, "Unknown section '\(move.toSection.rawValue)'")
        }

        // .activeSpace omits the on-screen filter, so it includes the hidden /
        // alwaysHidden divider control items even when collapsed off-screen.
        let items = await MenuBarItem.getMenuBarItems(option: .activeSpace)

        guard let source = items.first(where: { item in
            guard !item.isControlItem else { return false }
            let bundleID = item.sourceApplication?.bundleIdentifier
                ?? item.owningApplication?.bundleIdentifier
            return bundleID == move.bundleID
        }) else {
            return (false, "Item '\(move.bundleID)' not found in the menu bar")
        }

        let destination: MenuBarItemManager.MoveDestination
        switch section {
        case .visible:
            guard let hiddenCI = items.first(matching: .hiddenControlItem) else {
                return (false, controlItemDiagnostic("hidden", items))
            }
            destination = .rightOfItem(hiddenCI)
        case .hidden:
            guard let hiddenCI = items.first(matching: .hiddenControlItem) else {
                return (false, controlItemDiagnostic("hidden", items))
            }
            destination = .leftOfItem(hiddenCI)
        case .alwaysHidden:
            guard let alwaysHiddenCI = items.first(matching: .alwaysHiddenControlItem) else {
                return (false, controlItemDiagnostic("alwaysHidden", items))
            }
            destination = .leftOfItem(alwaysHiddenCI)
        }

        do {
            try await appState.itemManager.move(item: source, to: destination)
            return (true, nil)
        } catch {
            return (false, "\(error)")
        }
    }

    private func controlItemDiagnostic(_ which: String, _ items: [MenuBarItem]) -> String {
        let controlTags = items
            .filter { $0.isControlItem }
            .map { "\($0.tag)" }
            .joined(separator: ", ")
        return "\(which) control item not found. Enumerated \(items.count) items; control items present: [\(controlTags)]. Is the section enabled in Settings?"
    }
}

// MARK: - Section mapping

private extension MenuBarSection.Name {
    /// Maps the trigger/wire section vocabulary to Ice's section names.
    /// The wire uses `alwaysVisible`; Ice calls the same section `visible`.
    init?(triggerSection: TriggerSection) {
        switch triggerSection {
        case .alwaysVisible: self = .visible
        case .hidden:        self = .hidden
        case .alwaysHidden:  self = .alwaysHidden
        }
    }
}
