//
//  MCPTriggerCommandHandler.swift
//  Ice
//
//  Fulfiller for the AI-Native Triggers create/manage surface (fire.10 P1).
//  Proposals from an agent's `set_trigger` / `list_triggers` /
//  `remove_trigger` calls are relayed from MCPBackend.xpc by `MCPRelayPump`
//  (since fire.10.2; a polled file channel before that) and fulfilled HERE —
//  where the TCC-bearing main app, the consent UI, the sealed-grant store,
//  and the authoritative `TriggerStore` all live.
//
//  Authority boundary
//  ------------------
//  The relay is only a request queue. Installing a trigger always passes
//  through `AutomationAuthorization.authorizeInstall` (its OWN consent
//  prompt — never the MCPWriteAuthorization 5-minute move lease); removal
//  passes through `authorizeRemoval`. The agent supplies a spec; Fire
//  generates the prompt, validates + clamps the spec, mints the id, and
//  binds approval to the exact write set via an HMAC-sealed grant.
//

import Foundation
import OSLog

@MainActor
final class MCPTriggerCommandHandler {
    private weak var appState: AppState?
    private let logger = Logger(category: "MCPTriggerCommandHandler")

    func performSetup(with appState: AppState) {
        self.appState = appState
        logger.debug("MCP trigger command handler active (relay fulfiller)")
    }

    /// Fulfills one relayed proposal: staleness check, then the op-specific
    /// flow (install consent / removal confirm / authoritative list). Called
    /// by `MCPRelayPump`, which processes one item at a time, so consent
    /// prompts never stack.
    func fulfill(_ proposal: MCPTriggerChannel.Proposal) -> MCPTriggerChannel.Result {
        logger.log("MCP trigger proposal received: \(proposal.id, privacy: .public) op=\(proposal.op.rawValue, privacy: .public)")

        // Refuse proposals that sat queued past their shelf life. Checked
        // BEFORE any prompt, so a slow human approval still completes.
        let age = Date().timeIntervalSince1970 - proposal.createdAt
        guard age <= MCPTriggerChannel.staleAfter else {
            logger.notice("Dropping stale trigger proposal \(proposal.id, privacy: .public) (age \(age, format: .fixed(precision: 1))s)")
            return failure(proposal, "Proposal expired before Fire could process it.")
        }

        switch proposal.op {
        case .install:
            return install(proposal)
        case .remove:
            return remove(proposal)
        case .list:
            return list(proposal)
        }
    }

    // MARK: - Install

    private func install(_ proposal: MCPTriggerChannel.Proposal) -> MCPTriggerChannel.Result {
        guard let spec = proposal.spec else {
            return failure(proposal, "Missing trigger spec")
        }

        let rule: TriggerRule
        do {
            rule = try TriggerSpecTranslator.makeRule(from: spec)
        } catch {
            let message = (error as? TriggerSpecTranslator.TranslationError)?.message
                ?? error.localizedDescription
            logger.notice("Trigger spec rejected: \(message, privacy: .public)")
            return failure(proposal, "Invalid trigger: \(message)")
        }

        guard let decision = AutomationAuthorization.shared.authorizeInstall(rule: rule) else {
            return failure(proposal, "Not approved in Fire.")
        }

        var approvedRule = rule
        approvedRule.enabled = decision.enable
        TriggerStore.shared.upsert(approvedRule, grant: decision.grant)
        appState?.triggerEngine.reload()

        logger.log("Installed trigger \(approvedRule.id, privacy: .public) enabled=\(decision.enable)")
        return MCPTriggerChannel.Result(
            id: proposal.id,
            success: true,
            triggerID: approvedRule.id.uuidString,
            enabled: decision.enable,
            triggers: nil,
            message: decision.enable
                ? "Installed and enabled “\(approvedRule.name)”."
                : "Installed “\(approvedRule.name)” (disabled — enable it in Fire ▸ Settings ▸ Automations).",
            completedAt: Date().timeIntervalSince1970
        )
    }

    // MARK: - Remove

    private func remove(_ proposal: MCPTriggerChannel.Proposal) -> MCPTriggerChannel.Result {
        guard let raw = proposal.triggerID, let id = UUID(uuidString: raw) else {
            return failure(proposal, "Missing or malformed trigger id")
        }
        guard let rule = TriggerStore.shared.rules.first(where: { $0.id == id }) else {
            return failure(proposal, "No automation with id \(raw)")
        }
        guard AutomationAuthorization.shared.authorizeRemoval(rule: rule) else {
            return failure(proposal, "Removal cancelled in Fire.")
        }

        TriggerStore.shared.remove(id: id)
        appState?.triggerEngine.reload()

        logger.log("Removed trigger \(id, privacy: .public)")
        return MCPTriggerChannel.Result(
            id: proposal.id,
            success: true,
            triggerID: raw,
            enabled: false,
            triggers: nil,
            message: "Removed “\(rule.name)”.",
            completedAt: Date().timeIntervalSince1970
        )
    }

    // MARK: - List

    private func list(_ proposal: MCPTriggerChannel.Proposal) -> MCPTriggerChannel.Result {
        let summaries = TriggerStore.shared.rules.map(MenuBarItemService.TriggerSummary.init(rule:))
        return MCPTriggerChannel.Result(
            id: proposal.id,
            success: true,
            triggerID: nil,
            enabled: false,
            triggers: summaries,
            message: nil,
            completedAt: Date().timeIntervalSince1970
        )
    }

    // MARK: - Helpers

    private func failure(_ proposal: MCPTriggerChannel.Proposal, _ message: String) -> MCPTriggerChannel.Result {
        MCPTriggerChannel.Result(
            id: proposal.id,
            success: false,
            triggerID: nil,
            enabled: false,
            triggers: nil,
            message: message,
            completedAt: Date().timeIntervalSince1970
        )
    }
}
