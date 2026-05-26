//
//  MCPBackend.swift
//  Ice
//
//  In-process XPC listener for the MCP backend. Unlike
//  MenuBarItemService (which runs in its own XPC subprocess), this
//  listener lives inside the Ice main app process so it has direct
//  access to the populated `MenuBarItemManager.shared.itemCache` and
//  can call `MenuBarItemManager.shared.move(item:to:)` for write ops
//  without any cross-process state mirroring.
//
//  Wire contract is identical to MenuBarItemService — same Request /
//  Response types from Shared/Services/MenuBarItemService.swift —
//  but listening on a different Mach service name so the bridge can
//  target it specifically. fire.6's MenuBarItemService still serves
//  legacy `sourcePID` lookups and the wire-only stub path; new MCP
//  clients (fire.7+) talk to this backend instead.
//
//  Why a separate service name (com.jordanbaird.Ice.MCPBackend):
//  the existing MenuBarItemService is an embedded .xpc bundle that
//  spawns its own subprocess via launchd. Sharing the same service
//  name would route bridge connections to that subprocess (which
//  doesn't have access to MenuBarItemManager's populated state).
//  A distinct name guarantees launchd routes bridge connections to
//  the in-process listener registered here.
//

import Foundation
import OSLog
import XPC

/// In-process XPC listener for the MCP backend.
@available(macOS 26.0, *)
final class MCPBackend {
    /// The shared backend.
    static let shared = MCPBackend()

    /// The Mach service name. Must NOT collide with the legacy
    /// `MenuBarItemService` service name — clients connecting to
    /// this name expect direct in-process dispatch to the state
    /// manager (`MCPBackendStateManager.shared`).
    static let serviceName = "com.jordanbaird.Ice.MCPBackend"

    /// The underlying XPC listener object.
    private var listener: XPCListener?

    /// The connection's logger.
    private let logger = Logger(category: "MCPBackend")

    /// Creates the shared backend.
    private init() {}

    deinit {
        cancel()
    }

    /// Handles a received message. Synchronous (XPC handler signature) —
    /// async dispatches into `MCPBackendStateManager` (which is
    /// `@MainActor`-isolated under the hood) go through a Task /
    /// semaphore bridge.
    private func handleMessage(_ message: XPCReceivedMessage) -> MenuBarItemService.Response? {
        do {
            let request = try message.decode(as: MenuBarItemService.Request.self)
            switch request {
            case .start:
                logger.debug("MCPBackend received start request")
                return .start

            case .sourcePID:
                // The legacy sourcePID handshake belongs on
                // MenuBarItemService.xpc, not here. Bridge should
                // never send this to MCPBackend; if it does, surface
                // a clear failure rather than silently returning nil.
                logger.notice("MCPBackend received .sourcePID — not supported on this service; route to MenuBarItemService.")
                return .sourcePID(nil)

            // MARK: - MCP Server Extension (Phase 4.5)

            case .listItems(let section):
                let items = syncWait {
                    await MCPBackendStateManager.shared.listItems(section: section)
                }
                return .items(items)

            case .moveItem(let bundleID, let toSection, let toIndex):
                let result = syncWait {
                    await MCPBackendStateManager.shared.moveItem(
                        bundleID: bundleID,
                        toSection: toSection,
                        toIndex: toIndex
                    )
                }
                return .mutationResult(
                    success: result.success,
                    undoToken: nil,
                    message: result.message
                )

            case .hideItem(let bundleID):
                let result = syncWait {
                    await MCPBackendStateManager.shared.hideItem(bundleID: bundleID)
                }
                return .mutationResult(
                    success: result.success,
                    undoToken: nil,
                    message: result.message
                )

            case .showItem(let bundleID):
                let result = syncWait {
                    await MCPBackendStateManager.shared.showItem(bundleID: bundleID)
                }
                return .mutationResult(
                    success: result.success,
                    undoToken: nil,
                    message: result.message
                )

            case .applyLayout(let name):
                let result = syncWait {
                    await MCPBackendStateManager.shared.applyLayout(name: name)
                }
                return .mutationResult(
                    success: result.success,
                    undoToken: nil,
                    message: result.message
                )

            case .saveLayout(let name):
                let savedCount = syncWait {
                    await MCPBackendStateManager.shared.saveLayout(name: name)
                }
                if let savedCount {
                    return .layoutSaved(name: name, itemCount: savedCount)
                } else {
                    return .mutationResult(
                        success: false,
                        undoToken: nil,
                        message: "Failed to save layout"
                    )
                }
            }
        } catch {
            logger.error("MCPBackend failed to handle message with error \(error)")
            return nil
        }
    }

    /// Activates the listener with the same-team peer requirement
    /// when a team identifier is available (Developer ID builds),
    /// dropping it for ad-hoc builds where `.isFromSameTeam()` would
    /// silently reject every peer.
    func activate() {
        guard listener == nil else {
            logger.notice("MCPBackend listener is already active")
            return
        }

        logger.debug("Activating MCPBackend listener for \(Self.serviceName)")

        do {
            if MenuBarItemService.ownTeamIdentifier() != nil {
                listener = try XPCListener(
                    service: Self.serviceName,
                    requirement: .isFromSameTeam()
                ) { [weak self] request in
                    request.accept { message in
                        self?.handleMessage(message)
                    }
                }
            } else {
                listener = try XPCListener(service: Self.serviceName) { [weak self] request in
                    request.accept { message in
                        self?.handleMessage(message)
                    }
                }
            }
            logger.info("MCPBackend listener active on \(Self.serviceName)")
        } catch {
            logger.error("Failed to activate MCPBackend listener: \(error)")
        }
    }

    /// Cancels the listener.
    func cancel() {
        logger.debug("Canceling MCPBackend listener")
        listener?.cancel()
        listener = nil
    }
}

// MARK: - sync<->async bridge

/// Bridges an async function into a synchronous one by blocking the
/// current thread on a DispatchSemaphore. Used inside the XPC handler
/// closure (which must return synchronously) when the work needs to
/// hop to `@MainActor` for `MenuBarItemManager` access.
///
/// Same pattern as `MenuBarItemService/Listener.swift`'s historical
/// syncWait — XPC handler threads come from a dispatch pool, blocking
/// one here is acceptable; XPC routes concurrent messages to other
/// worker threads.
@inline(__always)
private func syncWait<T>(_ work: @escaping () async -> T) -> T {
    let semaphore = DispatchSemaphore(value: 0)
    var result: T!
    Task.detached {
        result = await work()
        semaphore.signal()
    }
    semaphore.wait()
    return result
}
