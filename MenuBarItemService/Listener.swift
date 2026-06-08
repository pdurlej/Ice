//
//  Listener.swift
//  MenuBarItemService
//

import OSLog
import XPC

/// A wrapper around an XPC listener object.
final class Listener {
    /// The shared listener.
    static let shared = Listener()

    /// The service name.
    private let name = MenuBarItemService.name

    /// The underlying XPC listener object.
    private var listener: XPCListener?

    /// Creates the shared listener.
    private init() { }

    deinit {
        cancel()
    }

    /// Handles a received message.
    private func handleMessage(_ message: XPCReceivedMessage) -> MenuBarItemService.Response? {
        do {
            let request = try message.decode(as: MenuBarItemService.Request.self)
            switch request {
            case .start:
                Logger.default.debug("Listener received start request")
                return .start

            case .sourcePID(let window):
                let pid = SourcePIDCache.shared.pid(for: window)
                return .sourcePID(pid)

            // MARK: - MCP Server Extension (Phase 4.5)

            case .listItems(let section):
                let items = MenuBarStateManager.shared.listItems(section: section)
                return .items(items)

            case .moveItem(let bundleID, let toSection, let toIndex):
                let result = MenuBarStateManager.shared.moveItem(
                    bundleID: bundleID,
                    toSection: toSection,
                    toIndex: toIndex
                )
                return .mutationResult(
                    success: result.success,
                    undoToken: nil,         // Phase 5 wires this
                    message: result.message
                )

            case .hideItem(let bundleID):
                let result = MenuBarStateManager.shared.hideItem(bundleID: bundleID)
                return .mutationResult(
                    success: result.success,
                    undoToken: nil,
                    message: result.message
                )

            case .showItem(let bundleID):
                let result = MenuBarStateManager.shared.showItem(bundleID: bundleID)
                return .mutationResult(
                    success: result.success,
                    undoToken: nil,
                    message: result.message
                )

            case .applyLayout(let name):
                let result = MenuBarStateManager.shared.applyLayout(name: name)
                return .mutationResult(
                    success: result.success,
                    undoToken: nil,
                    message: result.message
                )

            case .saveLayout(let name):
                if let savedCount = MenuBarStateManager.shared.saveLayout(name: name) {
                    return .layoutSaved(name: name, itemCount: savedCount)
                } else {
                    return .mutationResult(
                        success: false,
                        undoToken: nil,
                        message: "Failed to save layout"
                    )
                }

            case .listLayouts:
                let names = MenuBarStateManager.shared.listLayouts()
                return .layouts(names)

            // MARK: - AI-Native Triggers (fire.10 P1)
            //
            // Triggers are owned by MCPBackend.xpc (which relays to the main
            // app's consent gate). This legacy service never handles them; if a
            // misrouted client sends one, reject it explicitly.

            case .setTrigger, .removeTrigger:
                Logger.default.notice("Received trigger request - not supported on MenuBarItemService, route to MCPBackend")
                return .triggerResult(
                    success: false,
                    id: nil,
                    enabled: false,
                    message: "Triggers are not handled by this service."
                )

            case .listTriggers:
                Logger.default.notice("Received listTriggers - not supported on MenuBarItemService, route to MCPBackend")
                return .triggers([])
            }
        } catch {
            Logger.default.error("Listener failed to handle message with error \(error)")
            return nil
        }
    }

    /// Activates the listener without checking if it is already active,
    /// with the requirement that session peers must be signed with the
    /// same team identifier as the service process.
    @available(macOS 26.0, *)
    private func uncheckedActivateWithSameTeamRequirement() throws {
        listener = try XPCListener(service: name, requirement: .isFromSameTeam()) { [weak self] request in
            request.accept { message in
                self?.handleMessage(message)
            }
        }
    }

    /// Activates the listener without checking if it is already active.
    private func uncheckedActivate() throws {
        listener = try XPCListener(service: name) { [weak self] request in
            request.accept { message in
                self?.handleMessage(message)
            }
        }
    }

    /// Activates the listener.
    func activate() {
        guard listener == nil else {
            Logger.default.notice("Listener is already active")
            return
        }

        Logger.default.debug("Activating listener")

        do {
            // On macOS 26+ the listener can constrain peers by team
            // identifier, but only when we actually have a team
            // identifier to compare against. Ad-hoc-signed builds (every
            // community fork without an Apple Developer Program account)
            // have no team identifier and would reject every connection
            // — including their own parent app — silently. The shared
            // helper lives on MenuBarItemService so the matching guard
            // in MenuBarItemServiceConnection (the client side) uses
            // exactly the same predicate.
            if #available(macOS 26.0, *), MenuBarItemService.ownTeamIdentifier() != nil {
                try uncheckedActivateWithSameTeamRequirement()
            } else {
                try uncheckedActivate()
            }
        } catch {
            Logger.default.error("Failed to activate listener with error \(error)")
        }
    }

    /// Cancels the listener.
    func cancel() {
        Logger.default.debug("Canceling listener")
        listener.take()?.cancel()
    }
}
