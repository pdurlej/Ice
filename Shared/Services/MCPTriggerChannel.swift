//
//  MCPTriggerChannel.swift
//  Shared
//
//  A file-based proposal/result channel for AI-Native Triggers (fire.10 P1),
//  separate from `MCPWriteChannel` on purpose.
//
//  Why a separate channel
//  ----------------------
//  Installing a trigger mints a PERSISTENT, sealed capability — a different and
//  stronger authority than a single direct move (which `MCPWriteChannel` carries
//  and which may ride a 5-minute lease). Keeping the two paths in physically
//  separate files makes the trigger-install authority boundary impossible to
//  confuse with the move-write one, and lets each evolve independently. Per
//  GPT-5.5 Pro's hardening review, the trigger consent gate must never reuse the
//  move lease.
//
//  Flow
//  ----
//  MCPBackend.xpc writes a `Proposal` (install / remove / list); the Ice main
//  app's `MCPTriggerCommandHandler` polls for it, runs the appropriate consent
//  gate (install/remove) or reads its authoritative `TriggerStore` (list), and
//  writes a `Result`. MCPBackend polls for the matching result.
//
//  Same file hygiene as `MCPWriteChannel`: owner-only dir (0700) and files
//  (0600), regular-file + same-owner + size checks, fresh `Data(contentsOf:)`
//  reads (no cfprefsd caching). The hygiene is defense-in-depth — the real
//  authorization boundary is the main app's consent prompt, which a forged
//  proposal cannot bypass.
//

import Foundation

enum MCPTriggerChannel {
    /// Reuses the same per-user `…/com.jordanbaird.Ice/mcp/` directory as
    /// `MCPWriteChannel` (distinct file names), so both channels share one
    /// 0700 parent.
    static let directory = MCPWriteChannel.directory

    static let proposalURL = directory.appendingPathComponent("trigger-proposal.json")
    static let resultURL = directory.appendingPathComponent("trigger-result.json")

    /// What the agent is proposing.
    enum Op: String, Codable {
        /// Install a new automation (requires the main app's install consent).
        case install
        /// Remove an existing automation by id (requires a removal confirm).
        case remove
        /// List installed automations (read-only; no consent).
        case list
    }

    /// A proposal issued by MCPBackend, fulfilled by the Ice main app.
    struct Proposal: Codable {
        /// Unique per proposal so the result can be matched and stale results
        /// ignored.
        let id: String
        let op: Op
        /// Present for `.install`.
        let spec: MenuBarItemService.TriggerSpec?
        /// Present for `.remove`.
        let triggerID: String?
        /// Epoch seconds the proposal was created. Checked at pickup (before any
        /// prompt), so a slow human approval still completes.
        let createdAt: Double
    }

    /// The result of fulfilling a `Proposal`, written by the Ice main app.
    struct Result: Codable {
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

    /// Proposals older than this (seconds) are ignored by the main app.
    /// Staleness is checked at pickup — BEFORE any consent prompt — so a slow
    /// human approval still installs. Kept tight so a crashed MCPBackend can't
    /// leave a poison proposal that replays much later.
    static let staleAfter: TimeInterval = 15

    private static func ensureDirectory() {
        let fm = FileManager.default
        try? fm.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    /// Only trust a channel file that is a regular file (not a symlink), owned
    /// by THIS user, and of sane size. Hygiene, not authorization.
    private static func isTrustedLocalFile(_ url: URL) -> Bool {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: url.path) else { return false }
        guard (attrs[.type] as? FileAttributeType) == .typeRegular else { return false }
        guard let owner = attrs[.ownerAccountID] as? NSNumber, owner.uint32Value == getuid() else { return false }
        guard let size = attrs[.size] as? NSNumber, size.intValue <= 64 * 1024 else { return false }
        return true
    }

    // MARK: Proposal (MCPBackend writes, Ice reads)

    static func writeProposal(_ proposal: Proposal) throws {
        ensureDirectory()
        let data = try JSONEncoder().encode(proposal)
        try data.write(to: proposalURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: proposalURL.path
        )
    }

    static func readProposal() -> Proposal? {
        guard isTrustedLocalFile(proposalURL) else { return nil }
        guard let data = try? Data(contentsOf: proposalURL) else { return nil }
        return try? JSONDecoder().decode(Proposal.self, from: data)
    }

    // MARK: Result (Ice writes, MCPBackend reads)

    static func writeResult(_ result: Result) throws {
        ensureDirectory()
        let data = try JSONEncoder().encode(result)
        try data.write(to: resultURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: resultURL.path
        )
    }

    static func readResult() -> Result? {
        guard isTrustedLocalFile(resultURL) else { return nil }
        guard let data = try? Data(contentsOf: resultURL) else { return nil }
        return try? JSONDecoder().decode(Result.self, from: data)
    }
}
