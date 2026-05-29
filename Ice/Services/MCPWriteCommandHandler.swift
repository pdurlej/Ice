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

    private var cancellable: AnyCancellable?

    /// Performs setup: starts polling the shared command file.
    func performSetup(with appState: AppState) {
        self.appState = appState

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
        logger.log(
            "Executing MCP write command \(command.id, privacy: .public): \(command.op, privacy: .public) \(command.bundleID, privacy: .public) -> \(command.toSection, privacy: .public)"
        )

        Task {
            let result = await execute(command)
            do {
                try MCPWriteChannel.writeResult(result)
            } catch {
                logger.error("Failed to write MCP result: \(error, privacy: .public)")
            }
        }
    }

    private func execute(_ command: MCPWriteChannel.Command) async -> MCPWriteChannel.Result {
        func fail(_ message: String) -> MCPWriteChannel.Result {
            MCPWriteChannel.Result(
                id: command.id, success: false, message: message,
                completedAt: Date().timeIntervalSince1970
            )
        }
        func ok(_ message: String? = nil) -> MCPWriteChannel.Result {
            MCPWriteChannel.Result(
                id: command.id, success: true, message: message,
                completedAt: Date().timeIntervalSince1970
            )
        }

        guard command.op == "move" else {
            return fail("Unknown op '\(command.op)'")
        }
        guard let appState else {
            return fail("Ice app state unavailable")
        }
        guard let section = MenuBarSection.Name(mcpRawValue: command.toSection) else {
            return fail("Unknown section '\(command.toSection)'")
        }

        // Refresh the cache so we move against the current layout.
        await appState.itemManager.cacheItemsIfNeeded()
        let cache = appState.itemManager.itemCache

        // Find the source item by bundle ID. Skip Ice's own control
        // items (never user-movable) and match on the source/owning app.
        guard let source = cache.managedItems.first(where: { item in
            guard !item.isControlItem else { return false }
            let bundleID = item.sourceApplication?.bundleIdentifier
                ?? item.owningApplication?.bundleIdentifier
            return bundleID == command.bundleID
        }) else {
            return fail("Item '\(command.bundleID)' not found in the menu bar")
        }

        // Map the target section to a MoveDestination relative to a
        // control item, matching ItemCache.insert's canonical semantics:
        //   alwaysVisible -> rightOf(hiddenControlItem)  (visible[0])
        //   hidden        -> leftOf(hiddenControlItem)   (append hidden)
        //   alwaysHidden  -> leftOf(alwaysHiddenControlItem)
        let destination: MenuBarItemManager.MoveDestination
        switch section {
        case .visible:
            guard let hiddenCI = cache.managedItems.first(matching: .hiddenControlItem) else {
                return fail("Hidden control item not found (is the Hidden section enabled?)")
            }
            destination = .rightOfItem(hiddenCI)
        case .hidden:
            guard let hiddenCI = cache.managedItems.first(matching: .hiddenControlItem) else {
                return fail("Hidden control item not found (is the Hidden section enabled?)")
            }
            destination = .leftOfItem(hiddenCI)
        case .alwaysHidden:
            guard let alwaysHiddenCI = cache.managedItems.first(matching: .alwaysHiddenControlItem) else {
                return fail("Always-Hidden control item not found (is the Always-Hidden section enabled in Settings?)")
            }
            destination = .leftOfItem(alwaysHiddenCI)
        }

        // Expand the relevant section dividers so they're on-screen for
        // the duration of the drag. Ice's normal auto-rehide collapses
        // them again afterwards. Without this, a move targeting a
        // collapsed section drags toward an off-screen divider and the
        // window server may refuse the relocation.
        let expanded = expandSectionsForMove(to: section, appState: appState)
        defer { restoreSections(expanded) }

        // Give the dividers a beat to settle on-screen before dragging.
        try? await Task.sleep(for: .milliseconds(120))

        do {
            try await appState.itemManager.move(item: source, to: destination)
            return ok("Moved \(command.bundleID) to \(command.toSection)")
        } catch {
            return fail("\(error)")
        }
    }

    /// Forces the section dividers needed for a move to be on-screen.
    /// Returns the list of (section, previousState) to restore afterward.
    private func expandSectionsForMove(
        to target: MenuBarSection.Name, appState: AppState
    ) -> [(MenuBarSection, ControlItem.HidingState)] {
        // Moving into hidden needs the hidden divider on-screen; into
        // alwaysHidden needs both hidden and alwaysHidden on-screen.
        // Moving into visible only needs the hidden divider as a target,
        // which is on-screen whenever the hidden section is shown.
        let names: [MenuBarSection.Name]
        switch target {
        case .visible, .hidden: names = [.visible, .hidden]
        case .alwaysHidden:     names = [.visible, .hidden, .alwaysHidden]
        }
        var saved: [(MenuBarSection, ControlItem.HidingState)] = []
        for name in names {
            guard let section = appState.menuBarManager.section(withName: name) else { continue }
            saved.append((section, section.controlItem.state))
            section.controlItem.state = .showSection
        }
        return saved
    }

    private func restoreSections(_ saved: [(MenuBarSection, ControlItem.HidingState)]) {
        for (section, state) in saved {
            section.controlItem.state = state
        }
    }
}

// MARK: - Section name <-> MCP raw value

private extension MenuBarSection.Name {
    /// Maps the MCP wire section raw values to Ice's section names.
    /// The MCP wire uses `alwaysVisible`; Ice calls the same section
    /// `visible`.
    init?(mcpRawValue: String) {
        switch mcpRawValue {
        case "alwaysVisible": self = .visible
        case "hidden":        self = .hidden
        case "alwaysHidden":  self = .alwaysHidden
        default:              return nil
        }
    }
}
