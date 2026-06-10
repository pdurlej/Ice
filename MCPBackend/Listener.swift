//
//  Listener.swift
//  MCPBackend
//
//  XPC listener for the MCP backend service. Mirrors the structure of
//  MenuBarItemService/Listener.swift but is dedicated to MCP tool calls
//  from the IceMCPBridge binary.
//
//  Wire contract: shared with MenuBarItemService (the symlinked
//  MenuBarItemService.swift in Shared/Services/). This service ONLY
//  responds to the MCP-extension cases (listItems, moveItem, hideItem,
//  showItem, applyLayout, saveLayout, listLayouts). The legacy .start
//  and .sourcePID cases route to MenuBarItemService.xpc, not here -
//  if we receive one, it's a misrouted client.
//

import OSLog
import XPC

/// Wraps the XPC listener for the MCP backend service.
final class Listener {
    /// The shared listener.
    static let shared = Listener()

    /// The Mach service name. MUST match the bundle ID set in
    /// MCPBackend/Resources/Info.plist (which is set via Xcode's
    /// PRODUCT_BUNDLE_IDENTIFIER build setting on this target).
    private let name = "com.jordanbaird.Ice.MCPBackend"

    /// The underlying XPC listener object.
    private var listener: XPCListener?

    /// Logger scoped to this service.
    private let logger = Logger(category: "MCPBackend.Listener")

    private init() {}

    deinit {
        cancel()
    }

    /// Handles a received message. Synchronous - the async MCP-extension
    /// dispatches go through `syncWait(_:)` because XPC handler closures
    /// must return synchronously.
    private func handleMessage(_ message: XPCReceivedMessage) -> MenuBarItemService.Response? {
        do {
            let request = try message.decode(as: MenuBarItemService.Request.self)
            switch request {
            case .start:
                logger.debug("Received .start (legacy - belongs to MenuBarItemService, returning .start anyway)")
                return .start

            case .sourcePID:
                // MenuBarItemService owns sourcePID. If we receive one
                // here it's a misrouted client - surface nil rather than
                // duplicating SourcePIDCache.
                logger.notice("Received .sourcePID - not supported on MCPBackend, route to MenuBarItemService")
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
                    undoToken: nil, // Phase 5 wires this
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

            case .applyLayout(let layoutName):
                let result = syncWait {
                    await MCPBackendStateManager.shared.applyLayout(name: layoutName)
                }
                return .mutationResult(
                    success: result.success,
                    undoToken: nil,
                    message: result.message
                )

            case .saveLayout(let layoutName):
                let savedCount = syncWait {
                    await MCPBackendStateManager.shared.saveLayout(name: layoutName)
                }
                if let savedCount {
                    return .layoutSaved(name: layoutName, itemCount: savedCount)
                } else {
                    return .mutationResult(
                        success: false,
                        undoToken: nil,
                        message: "Failed to save layout"
                    )
                }

            case .listLayouts:
                let names = MCPBackendStateManager.shared.listLayouts()
                return .layouts(names)

            // MARK: - AI-Native Triggers (fire.10 P1)

            case .setTrigger(let spec):
                let result = syncWait {
                    await MCPBackendStateManager.shared.setTrigger(spec: spec)
                }
                return .triggerResult(
                    success: result.success,
                    id: result.triggerID,
                    enabled: result.enabled,
                    message: result.message
                )

            case .listTriggers:
                let summaries = syncWait {
                    await MCPBackendStateManager.shared.listTriggers()
                }
                return .triggers(summaries)

            case .removeTrigger(let id):
                let result = syncWait {
                    await MCPBackendStateManager.shared.removeTrigger(id: id)
                }
                return .triggerResult(
                    success: result.success,
                    id: result.triggerID,
                    enabled: false,
                    message: result.message
                )

            // MARK: - Main-app relay (fire.10.2)
            //
            // The Ice main app pulls queued agent work and pushes results
            // back over its own authenticated XPCSession. Same peer gating
            // as every other message on this listener.

            case .relayFetch:
                let work = syncWait { await RelayQueue.shared.dequeue() }
                return .relayWork(work)

            case .relayComplete(let result):
                syncWait { await RelayQueue.shared.complete(result) }
                return .relayAck
            }
        } catch {
            logger.error("Failed to handle message: \(error)")
            return nil
        }
    }

    /// Activates the listener. Uses the same-team peer requirement when
    /// the service has a Team Identifier (Developer ID build), skips it
    /// otherwise (ad-hoc builds without Apple Developer Program).
    func activate() {
        guard listener == nil else {
            logger.notice("Listener already active")
            return
        }

        logger.debug("Activating MCPBackend listener for \(self.name)")

        do {
            if #available(macOS 26.0, *), MenuBarItemService.ownTeamIdentifier() != nil {
                listener = try XPCListener(
                    service: name,
                    requirement: .isFromSameTeam()
                ) { [weak self] request in
                    request.accept { message in
                        self?.handleMessage(message)
                    }
                }
            } else {
                listener = try XPCListener(service: name) { [weak self] request in
                    request.accept { message in
                        self?.handleMessage(message)
                    }
                }
            }
            logger.info("MCPBackend listener active")
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
/// current thread on a DispatchSemaphore. Necessary because XPC handler
/// closures expect a synchronous return; the MCPBackendStateManager
/// methods are async (some hop to @MainActor for AX work).
///
/// XPC handler threads come from a dispatch pool; blocking one is
/// acceptable - XPC routes concurrent messages to other worker threads.
@inline(__always)
func syncWait<T>(_ work: @escaping () async -> T) -> T {
    let semaphore = DispatchSemaphore(value: 0)
    var result: T!
    Task.detached {
        result = await work()
        semaphore.signal()
    }
    semaphore.wait()
    return result
}
