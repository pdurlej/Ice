//
//  AIQuotaSettingsSection.swift
//  Ice
//
//  The AI Quotas controls shown inside the Advanced settings pane.
//  Bound to the live AIQuotaSettings so toggles take effect immediately.
//

import SwiftUI

struct AIQuotaSettingsContent: View {
    @ObservedObject var settings: AIQuotaSettings

    var body: some View {
        description
        enableToggle
        providerToggles
        cliPathField
    }

    @ViewBuilder
    private var description: some View {
        Text(
            """
            AI Quotas reads provider usage from a local CodexBar CLI \
            installation and shows each provider's weekly usage in the \
            menu bar. Fire does not send usage data anywhere. Default: off.
            """
        )
        .padding(.trailing, 75)
    }

    @ViewBuilder
    private var enableToggle: some View {
        Toggle("Enable AI Quotas", isOn: $settings.enableAIQuotas)
    }

    @ViewBuilder
    private var providerToggles: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Providers")
            ForEach(AIQuotaProvider.allCases) { provider in
                Toggle(provider.displayName, isOn: binding(for: provider))
                    .disabled(!settings.enableAIQuotas)
            }
        }
    }

    /// A Bool binding for whether a provider is in the enabled set.
    private func binding(for provider: AIQuotaProvider) -> Binding<Bool> {
        Binding(
            get: { settings.enabledProviders.contains(provider) },
            set: { isOn in
                if isOn {
                    settings.enabledProviders.insert(provider)
                } else {
                    settings.enabledProviders.remove(provider)
                }
            }
        )
    }

    @ViewBuilder
    private var cliPathField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("CodexBar CLI path (optional)")
            TextField(
                "/opt/homebrew/bin/codexbar",
                text: $settings.codexBarCLIPath
            )
            .textFieldStyle(.roundedBorder)
            .disabled(!settings.enableAIQuotas)
        }
        .annotation {
            Text("Leave empty to auto-detect codexbar in the usual locations.")
                .padding(.trailing, 75)
        }
    }
}
