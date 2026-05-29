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
        compactToggle
        cliPathField
    }

    @ViewBuilder
    private var description: some View {
        Text(
            """
            AI Quotas uses a local CodexBar CLI installation to read \
            provider usage (Codex, Claude, Gemini, Ollama) and shows \
            remaining limits in the menu bar. Fire does not send usage \
            data anywhere. Default: off.
            """
        )
        .padding(.trailing, 75)
    }

    @ViewBuilder
    private var enableToggle: some View {
        Toggle("Enable AI Quotas", isOn: $settings.enableAIQuotas)
    }

    @ViewBuilder
    private var compactToggle: some View {
        Toggle("Compact title (hide the leading \"AI\")", isOn: $settings.compactTitle)
            .disabled(!settings.enableAIQuotas)
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
