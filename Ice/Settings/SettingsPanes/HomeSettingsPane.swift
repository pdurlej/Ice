import SwiftUI

struct HomeSettingsPane: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var contextStore = TriggerStore.shared

    private var permissionHealth: (value: String, ready: Bool) {
        switch appState.permissions.permissionsState {
        case .hasAll:
            ("Ready", true)
        case .hasRequired:
            ("Limited mode", true)
        case .missing:
            ("Needs attention", false)
        }
    }

    private var mcpStatus: String {
        let settings = appState.settings.advanced
        if !settings.mcpServerEnabled { return "Off" }
        return settings.mcpAllowWrites ? "Ready for approved changes" : "Read only"
    }

    var body: some View {
        IceForm {
            IceSection("Ignition") {
                Text("Fire programs your menu bar for the work happening now.")
                    .font(.title2.weight(.semibold))
                Text(
                    "Grant the local permissions, connect one coding agent, then ask it to create your first Context Scene."
                )
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.trailing, 75)
            }

            IceSection("Setup health") {
                healthRow("System permissions", value: permissionHealth.value, ready: permissionHealth.ready)
                healthRow("Local agent bridge", value: mcpStatus, ready: appState.settings.advanced.mcpServerEnabled)
                healthRow(
                    "Context Scenes",
                    value: contextStore.rules.isEmpty ? "None yet" : "\(contextStore.rules.count) installed",
                    ready: !contextStore.rules.isEmpty
                )
            }

            IceSection("System permissions") {
                ForEach(appState.permissions.allPermissions) { permission in
                    LabeledContent {
                        if permission.hasPermission {
                            Label("Granted", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Button("Grant…") { permission.performRequest() }
                                .accessibilityLabel("Grant \(permission.title) permission")
                        }
                    } label: {
                        Text(permission.title)
                    }
                    .frame(height: 24)
                }
                Text("macOS may list Fire as Ice to preserve your existing permission grants.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            IceSection("First context") {
                Text("Connect Codex, Claude Code, or OpenCode, then try:")
                    .foregroundStyle(.secondary)
                Text("“When I work in Codex, show my quota in Fireline.”")
                    .textSelection(.enabled)
                HStack {
                    Button("Set up an agent") {
                        appState.navigationState.settingsNavigationIdentifier = .agents
                    }
                    Button("Arrange surfaces") {
                        appState.navigationState.settingsNavigationIdentifier = .surfaces
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func healthRow(_ title: String, value: String, ready: Bool) -> some View {
        LabeledContent {
            Label(value, systemImage: ready ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(ready ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                .accessibilityLabel("\(title): \(value)")
        } label: {
            Text(title)
        }
    }
}
