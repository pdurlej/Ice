//
//  MCPTriggerCommandHandler.swift
//  Ice
//
//  Ice-main-app side of the AI-Native Triggers create/manage surface
//  (fire.10 P1). Polls the `MCPTriggerChannel` for proposals that
//  MCPBackend.xpc relays from an agent's `set_trigger` / `list_triggers` /
//  `remove_trigger` calls, and fulfills each one HERE — where the TCC-bearing
//  main app, the consent UI, the sealed-grant store, and the authoritative
//  `TriggerStore` all live.
//
//  Authority boundary
//  ------------------
//  The channel is only a request queue. Installing a trigger always passes
//  through `AutomationAuthorization.authorizeInstall` (its OWN consent prompt —
//  never the MCPWriteAuthorization 5-minute move lease); removal passes through
//  `authorizeRemoval`. The agent supplies a spec; Fire generates the prompt,
//  validates + clamps the spec, mints the id, and binds approval to the exact
//  write set via an HMAC-sealed grant. A forged proposal cannot bypass the
//  prompt.
//

import Combine
import Foundation
import OSLog

@MainActor
final class MCPTriggerCommandHandler {
    private weak var appState: AppState?
    private let logger = Logger(category: "MCPTriggerCommandHandler")

    /// Last proposal id processed, so a single proposal isn't re-run on every
    /// poll tick.
    private var lastProcessedID: String?

    /// True while a consent prompt is on screen, so concurrent poll ticks don't
    /// stack a second modal.
    private var inFlight = false

    private var cancellable: AnyCancellable?

    func performSetup(with appState: AppState) {
        self.appState = appState

        // Coarse poll, same cadence as the move channel — immediate enough for
        // an interactive create flow without busy-spinning.
        cancellable = Timer.publish(every: 0.2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.poll()
            }
        logger.debug("MCP trigger command handler active")
    }

    private func poll() {
        guard !inFlight else { return }
        guard let proposal = MCPTriggerChannel.readProposal() else { return }
        guard proposal.id != lastProcessedID else { return }
        logger.log("MCP trigger proposal received: \(proposal.id, privacy: .public) op=\(proposal.op.rawValue, privacy: .public)")

        // Ignore poison/stale proposals left by a crashed MCPBackend. Checked
        // BEFORE any prompt, so a slow human approval still completes.
        let age = Date().timeIntervalSince1970 - proposal.createdAt
        guard age <= MCPTriggerChannel.staleAfter else {
            lastProcessedID = proposal.id
            logger.notice("Dropping stale trigger proposal \(proposal.id, privacy: .public) (age \(age, format: .fixed(precision: 1))s)")
            return
        }

        lastProcessedID = proposal.id
        inFlight = true

        Task { @MainActor in
            defer { inFlight = false }
            let result = fulfill(proposal)
            do {
                try MCPTriggerChannel.writeResult(result)
            } catch {
                logger.error("Failed to write trigger result: \(error, privacy: .public)")
            }
        }
    }

    private func fulfill(_ proposal: MCPTriggerChannel.Proposal) -> MCPTriggerChannel.Result {
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
