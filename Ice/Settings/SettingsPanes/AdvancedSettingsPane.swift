//
//  AdvancedSettingsPane.swift
//  Ice
//

import SwiftUI

struct AdvancedSettingsPane: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var settings: AdvancedSettings
    @State private var maxSliderLabelWidth: CGFloat = 0

    private var menuBarManager: MenuBarManager {
        appState.menuBarManager
    }

    private func formattedToSeconds(_ interval: TimeInterval) -> LocalizedStringKey {
        let formatted = interval.formatted()
        return if interval == 1 {
            LocalizedStringKey(formatted + " second")
        } else {
            LocalizedStringKey(formatted + " seconds")
        }
    }

    var body: some View {
        IceForm {
            IceSection("Menu Bar Sections") {
                enableAlwaysHiddenSection
                showAllSectionsOnUserDrag
                sectionDividerStyle
            }
            IceSection("Other") {
                hideApplicationMenus
                enableSecondaryContextMenu
                showOnHoverDelay
                tempShowInterval
            }
            IceSection("Permissions") {
                allPermissions
            }
            IceSection("Privacy & Diagnostics") {
                shareDiagnostics
            }
            IceSection("Contexts & Agents") {
                contextsAndAgentsEnabled
            }
            if settings.contextsAndAgentsEnabled {
                IceSection("MCP Server (experimental)") {
                    mcpServerDescription
                    mcpServerEnabled
                    mcpAllowWrites
                    mcpNotifyOnWrite
                }
                IceSection("AI Quotas (experimental)") {
                    AIQuotaSettingsContent(settings: appState.aiQuotaManager.settings)
                }
            }
        }
    }

    @ViewBuilder
    private var contextsAndAgentsEnabled: some View {
        Toggle(
            "Enable Contexts & Agents",
            isOn: $settings.contextsAndAgentsEnabled
        )
        .annotation {
            Text(
                "Optional local AI features. When off, Fire runs only its menu bar manager and does not start MCP, triggers, or quota polling."
            )
            .padding(.trailing, 75)
        }
    }

    @ViewBuilder
    private var shareDiagnostics: some View {
        Toggle(
            "Share anonymous crash reports with the Fire fork maintainer",
            isOn: $settings.shareDiagnostics
        )
        .annotation {
            Text(
                """
                When enabled, sends crash reports (stack trace + thread state + \
                macOS version + Ice version) to the Fire fork maintainer via Sentry. \
                Never sends your hostname, IP address, menu bar item contents, \
                screenshots, or any usage telemetry. Takes effect after the next \
                app launch. Default: off.
                """
            )
            .padding(.trailing, 75)
        }
    }

    @ViewBuilder
    private var mcpServerDescription: some View {
        Text(
            """
            Lets AI assistants (Claude Desktop, Claude Code, Cursor, Continue) \
            read and modify your menu bar layout via the Model Context Protocol. \
            See docs/mcp/CLIENT-SETUP.md for setup.
            """
        )
        .padding(.trailing, 75)
    }

    @ViewBuilder
    private var mcpServerEnabled: some View {
        Toggle(
            "Enable MCP server",
            isOn: $settings.mcpServerEnabled
        )
        .annotation {
            Text(
                """
                The master switch. When off, Fire refuses every request from AI \
                assistants — both reads and writes. Default: off (turn it on to opt in).
                """
            )
            .padding(.trailing, 75)
        }
    }

    @ViewBuilder
    private var mcpAllowWrites: some View {
        Toggle(
            "Allow write operations",
            isOn: $settings.mcpAllowWrites
        )
        .disabled(!settings.mcpServerEnabled)
        .annotation {
            Text(
                """
                When off, AI assistants can read your layout (list_items) but cannot \
                change it — moving, hiding, saving layouts, and automations are all \
                refused. Default: off.
                """
            )
            .padding(.trailing, 75)
        }
    }

    @ViewBuilder
    private var mcpNotifyOnWrite: some View {
        Toggle(
            "Notify on write operations",
            isOn: $settings.mcpNotifyOnWrite
        )
        .disabled(!settings.mcpServerEnabled || !settings.mcpAllowWrites)
        .annotation {
            Text("Posts a notification each time an AI assistant changes your menu bar.")
                .padding(.trailing, 75)
        }
    }

    @ViewBuilder
    private var enableAlwaysHiddenSection: some View {
        Toggle(
            "Enable the always-hidden section",
            isOn: $settings.enableAlwaysHiddenSection
        )
    }

    @ViewBuilder
    private var showAllSectionsOnUserDrag: some View {
        Toggle(
            "Show all sections when ⌘ Command + dragging menu bar items",
            isOn: $settings.showAllSectionsOnUserDrag
        )
    }

    @ViewBuilder
    private var sectionDividerStyle: some View {
        IcePicker("Section divider style", selection: $settings.sectionDividerStyle) {
            ForEach(SectionDividerStyle.allCases) { style in
                Text(style.localized).tag(style)
            }
        }
    }

    @ViewBuilder
    private var hideApplicationMenus: some View {
        Toggle(
            "Hide app menus when showing menu bar items",
            isOn: $settings.hideApplicationMenus
        )
        .annotation {
            Text(
                """
                Make more room in the menu bar by hiding the current app menus if \
                needed. macOS requires Ice to make itself visible in the Dock while \
                this setting is in effect.
                """
            )
            .padding(.trailing, 75)
        }
    }

    @ViewBuilder
    private var enableSecondaryContextMenu: some View {
        Toggle(
            "Enable secondary context menu",
            isOn: $settings.enableSecondaryContextMenu
        )
        .annotation {
            Text(
                """
                Right-click in an empty area of the menu bar to display a minimal \
                version of Ice's menu. Disable this setting if you encounter conflicts \
                with other apps.
                """
            )
            .padding(.trailing, 75)
        }
    }

    @ViewBuilder
    private var showOnHoverDelay: some View {
        LabeledContent {
            IceSlider(
                formattedToSeconds(settings.showOnHoverDelay),
                value: $settings.showOnHoverDelay,
                in: 0...1,
                step: 0.1
            )
        } label: {
            Text("Show on hover delay")
                .frame(minWidth: maxSliderLabelWidth, alignment: .leading)
                .onFrameChange { frame in
                    maxSliderLabelWidth = max(maxSliderLabelWidth, frame.width)
                }
        }
        .annotation("The amount of time to wait before showing on hover.")
    }

    @ViewBuilder
    private var tempShowInterval: some View {
        LabeledContent {
            IceSlider(
                formattedToSeconds(settings.tempShowInterval),
                value: $settings.tempShowInterval,
                in: 0...60,
                step: 1
            )
        } label: {
            Text("Temporarily shown item delay")
                .frame(minWidth: maxSliderLabelWidth, alignment: .leading)
                .onFrameChange { frame in
                    maxSliderLabelWidth = max(maxSliderLabelWidth, frame.width)
                }
        }
        .annotation("The amount of time to wait before hiding temporarily shown menu bar items.")
    }

    @ViewBuilder
    private var allPermissions: some View {
        ForEach(appState.permissions.allPermissions) { permission in
            LabeledContent {
                if permission.hasPermission {
                    Label {
                        Text("Permission Granted")
                    } icon: {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(.green)
                    }
                } else {
                    Button("Grant Permission") {
                        permission.performRequest()
                    }
                }
            } label: {
                Text(permission.title)
            }
            .frame(height: 22)
        }
    }
}
