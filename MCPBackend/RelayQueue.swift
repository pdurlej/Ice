//
//  RelayQueue.swift
//  MCPBackend
//
//  In-memory hand-off between agent-originated XPC calls (from IceMCPBridge)
//  and the Ice main app's relay pump (fire.10.2).
//
//  A bridge call submits its command/proposal here and suspends until the
//  main app fetches it (`.relayFetch`), fulfills it (consent + execution),
//  and posts the result (`.relayComplete`) — or until the per-call timeout
//  expires. This replaced the fire.8.2 single-slot file channel: requests
//  queue FIFO (no overwrite races), the transport is the authenticated XPC
//  connection, and there is no file IO anywhere on the path.
//
//  Continuation discipline: every waiter is resumed EXACTLY once. Both
//  resume sites go through `waiters.removeValue(forKey:)` on the actor, so
//  a timeout/complete race cannot double-resume (the codexbar-timeout
//  lesson, applied). A result arriving after its waiter timed out is logged
//  and dropped — the bridge already answered the agent.
//

import Foundation
import OSLog

actor RelayQueue {
    static let shared = RelayQueue()

    /// FIFO of work awaiting a main-app fetch.
    private var pending: [MenuBarItemService.RelayWork] = []

    /// Bridge calls suspended until their result arrives, keyed by work id.
    private var waiters: [String: CheckedContinuation<MenuBarItemService.RelayResult?, Never>] = [:]

    private let logger = Logger(category: "MCPBackend.RelayQueue")

    private init() {}

    /// Queues `work` and suspends until the main app posts its result, or
    /// until `timeout` elapses (returns nil). Generous timeouts are expected
    /// for consent-gated work — a human reads the prompt.
    func submitAndWait(
        _ work: MenuBarItemService.RelayWork,
        timeout: TimeInterval
    ) async -> MenuBarItemService.RelayResult? {
        let id = work.id
        pending.append(work)
        logger.debug("Queued relay work \(id, privacy: .public) (pending: \(self.pending.count))")
        return await withCheckedContinuation { continuation in
            waiters[id] = continuation
            Task {
                try? await Task.sleep(for: .seconds(timeout))
                self.expire(id: id)
            }
        }
    }

    /// The next queued item for the main app, if any.
    func dequeue() -> MenuBarItemService.RelayWork? {
        guard !pending.isEmpty else { return nil }
        return pending.removeFirst()
    }

    /// Delivers the main app's result to the suspended bridge call.
    func complete(_ result: MenuBarItemService.RelayResult) {
        guard let continuation = waiters.removeValue(forKey: result.id) else {
            logger.notice("Late relay result \(result.id, privacy: .public) dropped (waiter already timed out)")
            return
        }
        continuation.resume(returning: result)
    }

    private func expire(id: String) {
        guard let continuation = waiters.removeValue(forKey: id) else {
            return  // already completed
        }
        pending.removeAll { $0.id == id }  // un-queue if never fetched
        logger.notice("Relay work \(id, privacy: .public) timed out")
        continuation.resume(returning: nil)
    }
}
