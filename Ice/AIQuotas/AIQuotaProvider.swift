//
//  AIQuotaProvider.swift
//  Ice
//
//  Part of the optional, local-only "AI Quotas" feature: shows LLM
//  usage limits in the menu bar, backed by the CodexBar CLI.
//

import Foundation

/// An LLM provider whose usage quota AI Quotas can display.
///
/// Raw values match the CodexBar CLI's `--provider` argument so they
/// can be passed straight through.
enum AIQuotaProvider: String, CaseIterable, Identifiable, Codable {
    case codex
    case claude
    case gemini
    case ollama

    var id: String { rawValue }

    /// Two-letter label used in the combined menu-bar title.
    var shortLabel: String {
        switch self {
        case .codex: "Cx"
        case .claude: "Cl"
        case .gemini: "Gm"
        case .ollama: "Ol"
        }
    }

    /// Human-readable name used in the dropdown menu.
    var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude"
        case .gemini: "Gemini"
        case .ollama: "Ollama"
        }
    }
}
