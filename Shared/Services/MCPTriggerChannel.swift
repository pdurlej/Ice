//
//  MCPTriggerChannel.swift
//  Shared
//
//  Wire model for AI-Native Trigger proposals (fire.10 P1), kept separate
//  from `MCPWriteChannel` on purpose: installing a trigger mints a
//  PERSISTENT, sealed capability — a different and stronger authority than a
//  single direct move (which may ride a 5-minute lease). Distinct types keep
//  the two authority shapes impossible to confuse, and each can evolve
//  independently. The trigger consent gate never reuses the move lease.
//
//  Transport history matches MCPWriteChannel: single-slot JSON files in
//  fire.10.0–10.1, replaced in fire.10.2 by the authenticated XPC relay
//  (MCPBackend `RelayQueue` + main-app `MCPRelayPump`). Only the model types
//  remain here.
//

import Foundation

enum MCPTriggerChannel {
    /// What the agent is proposing.
    enum Op: String, Codable, Sendable {
        /// Install a new automation (requires the main app's install consent).
        case install
        /// Remove an existing automation by id (requires a removal confirm).
        case remove
        /// List installed automations (read-only; no consent).
        case list
    }

    /// A proposal issued by MCPBackend on behalf of an agent, fulfilled by
    /// the Ice main app.
    struct Proposal: Codable, Sendable {
        /// Unique per proposal, so the result can be correlated.
        let id: String
        let op: Op
        /// Present for `.install`.
        let spec: MenuBarItemService.TriggerSpec?
        /// Present for `.remove`.
        let triggerID: String?
        /// Epoch seconds the proposal was created. Checked at fetch time
        /// (before any prompt), so a slow human approval still completes.
        let createdAt: Double
    }

    /// The result of fulfilling a `Proposal`, produced by the Ice main app.
    struct Result: Codable, Sendable {
        let id: String
        let success: Bool
        /// Installed/removed trigger id (nil on failure/denial).
        let triggerID: String?
        /// Whether an installed trigger is enabled.
        let enabled: Bool
        /// Present for `.list`.
        let triggers: [MenuBarItemService.TriggerSummary]?
        /// User-facing message (denial reason, validation error, or summary).
        let message: String?
        let completedAt: Double
    }

    /// Proposals older than this (seconds) are refused by the main app at
    /// fetch time — BEFORE any consent prompt, so a slow human approval
    /// still installs.
    static let staleAfter: TimeInterval = 15
}
