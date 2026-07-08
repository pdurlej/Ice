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
            //
            // Every agent-facing request — reads INCLUDED — is owned by
            // MCPBackend.xpc, which enforces the Advanced → MCP kill-switch
            // (fire.10.4). This legacy service must NOT answer them: it once
            // served `.listItems` / `.saveLayout` / `.listLayouts` directly,
            // which leaked the menu-bar layout (and let a client persist saved
            // layouts) even with "Enable MCP server" OFF — bypassing the
            // kill-switch entirely (fire.10.5, issue #8). This service now does
            // ONLY its real job: the `.start` + `.sourcePID` handshake. A
            // request landing here for anything else is a misrouted client.

            case .listItems, .listLayouts:
                Logger.default.notice("Received read op - not served by this service, route to MCPBackend")
                return .denied("Menu bar reads are handled by MCPBackend, not this service.")

            case .moveItem, .hideItem, .showItem, .applyLayout, .saveLayout:
                Logger.default.notice("Received write op - not supported on MenuBarItemService, route to MCPBackend")
                return .denied("Write operations are handled by MCPBackend, not this service.")

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

            case .relayFetch, .relayComplete:
                Logger.default.notice("Received relay request - not supported on MenuBarItemService, route to MCPBackend")
                return .relayWork(nil)
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
