//
//  AgentsSettingsPane.swift
//  Ice
//

import AppKit
import SwiftUI

struct AgentsSettingsPane: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var settings: AdvancedSettings
    @State private var doctorResult: String?
    @State private var doctorRunning = false

    private let bridgePath = "/Applications/Ice.app/Contents/MacOS/IceMCPBridge"
    private let skillPath = "/Applications/Ice.app/Contents/Resources/AgentSkills/program-fire"

    private var openCodeFireBlock: String {
        """
        {
          "type": "local",
          "command": ["\(bridgePath)"],
          "enabled": true
        }
        """
    }

    var body: some View {
        IceForm {
            IceSection("Local agent bridge") {
                Toggle("Enable local MCP server", isOn: $settings.mcpServerEnabled)
                    .annotation("Allows explicitly configured local agents to inspect Fire. No network listener is created.")
                Toggle("Allow approved changes", isOn: $settings.mcpAllowWrites)
                    .disabled(!settings.mcpServerEnabled)
                    .annotation("Fire still presents and seals its own approval before installing Context Scenes or changing the menu bar.")
                Toggle("Notify after direct changes", isOn: $settings.mcpNotifyOnWrite)
                    .disabled(!settings.mcpServerEnabled || !settings.mcpAllowWrites)
            }

            IceSection("Connection test") {
                HStack {
                    Button(doctorRunning ? "Checking…" : "Run Fire Doctor") {
                        runDoctor()
                    }
                    .disabled(doctorRunning || !settings.mcpServerEnabled)
                    .accessibilityLabel("Run Fire agent connection test")
                    if let doctorResult {
                        Text(doctorResult)
                            .font(.callout)
                            .foregroundStyle(doctorResult.hasPrefix("Ready") ? .green : .secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            IceSection("Connect an agent") {
                Text("Fire ships one shared skill for Codex, Claude Code, and OpenCode. Setup only adds this local bridge and links that skill; it does not copy separate prompts.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.trailing, 75)
                setupRow(
                    "Codex",
                    detail: "codex mcp add fire -- \(bridgePath)",
                    copyValue: "codex mcp add fire -- \(bridgePath)"
                )
                setupRow(
                    "Claude Code",
                    detail: "claude mcp add --transport stdio --scope user fire -- \(bridgePath)",
                    copyValue: "claude mcp add --transport stdio --scope user fire -- \(bridgePath)"
                )
                setupRow(
                    "OpenCode",
                    detail: "Merge the copied block as mcp.fire in ~/.config/opencode/opencode.json",
                    copyValue: openCodeFireBlock,
                    buttonTitle: "Copy JSON"
                )
                setupRow(
                    "Shared skill",
                    detail: "Link one canonical skill for Codex, Claude Code, and OpenCode",
                    copyValue: "mkdir -p \"$HOME/.agents/skills\" \"$HOME/.claude/skills\" && ln -sfn \"\(skillPath)\" \"$HOME/.agents/skills/program-fire\" && ln -sfn \"\(skillPath)\" \"$HOME/.claude/skills/program-fire\""
                )
            }

            IceSection("AI quota providers") {
                AIQuotaSettingsContent(settings: appState.aiQuotaManager.settings)
            }
        }
    }

    @ViewBuilder
    private func setupRow(
        _ name: String,
        detail: String,
        copyValue: String,
        buttonTitle: String = "Copy setup"
    ) -> some View {
        LabeledContent {
            Button(buttonTitle) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(copyValue, forType: .string)
            }
            .accessibilityLabel("Copy \(name) setup instructions")
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                Text(detail)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
        }
    }

    private func runDoctor() {
        doctorRunning = true
        doctorResult = nil
        let executable = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/fire")

        Task {
            let result = await Task.detached(priority: .userInitiated) {
                let process = Process()
                let output = Pipe()
                let errors = Pipe()
                process.executableURL = executable
                process.arguments = ["doctor"]
                process.standardOutput = output
                process.standardError = errors
                do {
                    try process.run()
                    process.waitUntilExit()
                    let stdout = output.fileHandleForReading.readDataToEndOfFile()
                    let stderr = errors.fileHandleForReading.readDataToEndOfFile()
                    let text = String(bytes: stdout + stderr, encoding: .utf8)
                        ?? "Fire Doctor returned non-UTF-8 output"
                    let trimmedText = text
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return process.terminationStatus == 0
                        ? "Ready — \(trimmedText)"
                        : "Needs attention — \(trimmedText)"
                } catch {
                    return "Needs attention — \(error.localizedDescription)"
                }
            }.value
            doctorResult = result
            doctorRunning = false
        }
    }
}
