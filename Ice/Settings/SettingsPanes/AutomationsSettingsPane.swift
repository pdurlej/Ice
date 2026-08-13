//
//  AutomationsSettingsPane.swift
//  Ice
//
//  Settings ▸ Automations — the manage surface for AI-Native Triggers
//  (fire.10 P1). Lists installed automations and lets the user enable/disable,
//  re-approve (when a grant has expired), delete, and globally disable all.
//
//  Creation is intentionally NOT here: automations are created by asking an
//  MCP-connected AI assistant (set_trigger), which routes through Fire's
//  install consent prompt. This pane is the human's ongoing control panel over
//  what was approved.
//

import SwiftUI

struct AutomationsSettingsPane: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var store = TriggerStore.shared

    @State private var pendingDelete: TriggerRule?

    private var hasEnabled: Bool {
        store.rules.contains { $0.enabled }
    }

    var body: some View {
        IceForm {
            introSection
            if store.rules.isEmpty {
                emptySection
            } else {
                ForEach(store.rules) { rule in
                    IceSection {
                        ruleRow(rule)
                    }
                }
            }
        }
        .confirmationDialog(
            "Remove “\(pendingDelete?.name ?? "")”?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { rule in
            Button("Remove Automation", role: .destructive) {
                remove(rule)
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { _ in
            Text("This deletes the automation and its approval. You can re-create it later.")
        }
        .onAppear {
            TriggerStore.shared.load()
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var introSection: some View {
        IceSection("AI-Native Automations") {
            Text(
                """
                Automations rearrange your menu bar for you when something \
                happens — an app comes to the front, the battery runs low, or a \
                weekly time window begins. Ask an AI assistant connected to Fire \
                (via MCP) to create one, approve it once, and it runs on its own. \
                Every automation here was approved by you and is bound to the exact \
                items and destination shown.
                """
            )
            .fixedSize(horizontal: false, vertical: true)
            .padding(.trailing, 75)

            if !appState.settings.advanced.contextsAndAgentsEnabled {
                CalloutBox(
                    "Automations are paused while Contexts & Agents is off.",
                    systemImage: "pause.circle"
                )
            }

            if hasEnabled {
                HStack {
                    Spacer()
                    Button("Disable All") {
                        disableAll()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var emptySection: some View {
        IceSection {
            VStack(alignment: .center, spacing: 8) {
                Image(systemName: "wand.and.rays")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text("No automations yet")
                    .font(.headline)
                Text(emptyStateGuidance)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }

    private var emptyStateGuidance: String {
        if appState.settings.advanced.contextsAndAgentsEnabled {
            return "Ask an AI assistant connected to Fire to set one up, e.g. “when Slack is frontmost, hide my password manager.”"
        }
        return "Turn on Contexts & Agents in Advanced settings before creating an automation with an AI assistant."
    }

    // MARK: - Rule row

    @ViewBuilder
    private func ruleRow(_ rule: TriggerRule) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(rule.name)
                        .font(.headline)
                    Text("When \(TriggerNarrator.describe(rule.condition)), \(TriggerNarrator.describe(rule.onEnter)).")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    lastFiredLabel(rule)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 8) {
                    Toggle("", isOn: enabledBinding(for: rule))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .disabled(!rule.enabled && !store.hasValidGrant(for: rule))
                    Button {
                        pendingDelete = rule
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove this automation")
                }
            }

            if !rule.enabled, !store.hasValidGrant(for: rule) {
                reApprovalNotice(rule)
            }
        }
    }

    @ViewBuilder
    private func lastFiredLabel(_ rule: TriggerRule) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "clock")
            if let last = rule.lastFiredAt {
                Text("Last ran \(last, format: .relative(presentation: .named))")
            } else {
                Text("Hasn’t run yet")
            }
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
    }

    @ViewBuilder
    private func reApprovalNotice(_ rule: TriggerRule) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.trianglebadge.exclamationmark")
                .foregroundStyle(.orange)
            Text("Approval expired — this automation was changed and needs to be approved again before it can run.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Re-approve…") {
                reApprove(rule)
            }
        }
        .font(.caption)
        .padding(.top, 2)
    }

    // MARK: - Actions

    private func enabledBinding(for rule: TriggerRule) -> Binding<Bool> {
        Binding(
            get: { store.rules.first(where: { $0.id == rule.id })?.enabled ?? false },
            set: { newValue in setEnabled(newValue, rule: rule) }
        )
    }

    private func setEnabled(_ enabled: Bool, rule: TriggerRule) {
        // Enabling requires a still-valid sealed grant; the store refuses
        // otherwise and the toggle snaps back after reload.
        _ = TriggerStore.shared.setEnabled(enabled, id: rule.id)
        appState.triggerEngine.reload()
    }

    private func reApprove(_ rule: TriggerRule) {
        guard let decision = AutomationAuthorization.shared.authorizeInstall(rule: rule) else {
            return
        }
        var approved = rule
        approved.enabled = decision.enable
        TriggerStore.shared.upsert(approved, grant: decision.grant)
        appState.triggerEngine.reload()
    }

    private func remove(_ rule: TriggerRule) {
        TriggerStore.shared.remove(id: rule.id)
        appState.triggerEngine.reload()
    }

    private func disableAll() {
        TriggerStore.shared.disableAll()
        appState.triggerEngine.reload()
    }
}
