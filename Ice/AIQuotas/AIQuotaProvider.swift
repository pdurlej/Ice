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
    case antigravity
    case ollama
    // Note: standalone `gemini` was intentionally removed — Antigravity
    // is Google's Gemini-backed tool, so it already covers Gemini usage,
    // and the separate gemini provider only ever showed "?" here.

    var id: String { rawValue }

    /// Two-letter label used as a fallback when a brand icon is missing.
    var shortLabel: String {
        switch self {
        case .codex: "Cx"
        case .claude: "Cl"
        case .antigravity: "Ag"
        case .ollama: "Ol"
        }
    }

    /// Human-readable name used in the dropdown menu and settings.
    var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude"
        case .antigravity: "Antigravity"
        case .ollama: "Ollama"
        }
    }
}
