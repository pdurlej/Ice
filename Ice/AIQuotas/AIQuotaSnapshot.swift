//
//  AIQuotaSnapshot.swift
//  Ice
//
//  Value types describing a provider's usage quota at a point in time.
//  Local-only: these never leave the device (no Sentry, no MCP).
//

import Foundation

/// A single usage window (e.g. the rolling 5-hour session window, or
/// the weekly window) for a provider.
struct AIQuotaWindow: Equatable, Codable {
    enum Kind: String, Codable {
        case primary
        case secondary
        case tertiary
    }

    let kind: Kind
    /// Percent of the window consumed, 0...100, if known.
    let usedPercent: Double?
    /// Percent of the window remaining, 0...100, if known. Derived from
    /// `usedPercent` when the backend doesn't provide it directly.
    let leftPercent: Double?
    /// Length of the window in minutes (e.g. 300 = 5h, 10080 = 1 week).
    let windowMinutes: Int?
    /// When the window resets, if known.
    let resetsAt: Date?
}

/// A named per-model usage window (e.g. Antigravity exposes one per
/// Gemini model under `extraRateWindows`).
struct AIQuotaExtraWindow: Equatable, Codable {
    let id: String
    let title: String
    let usedPercent: Double?

    var leftPercent: Double? {
        usedPercent.map { 100 - $0 }
    }
}

/// A provider's full quota snapshot, including both windows, account
/// metadata, and any fetch error.
struct AIQuotaSnapshot: Equatable, Codable {
    let provider: AIQuotaProvider
    /// Where the data came from (e.g. "codex-cli", "claude-web").
    let source: String?
    /// When the backend last refreshed this data.
    let updatedAt: Date?
    /// The primary / session window.
    let primary: AIQuotaWindow?
    /// The secondary / weekly window.
    let secondary: AIQuotaWindow?
    /// A third window, when a provider exposes one.
    let tertiary: AIQuotaWindow?
    /// Per-model windows (e.g. Antigravity's Gemini models). Empty for
    /// providers that don't break usage down by model.
    let extraWindows: [AIQuotaExtraWindow]
    /// Account label (email) if available.
    let account: String?
    /// Plan / login method if available (e.g. "pro").
    let plan: String?
    /// Non-nil if the fetch failed; the snapshot is otherwise empty.
    let error: String?

    /// True when the snapshot carries at least one usable window and no
    /// error.
    var isUsable: Bool {
        error == nil && (primary != nil || secondary != nil || tertiary != nil || !extraWindows.isEmpty)
    }

    /// Convenience: an error-only snapshot for a provider.
    static func failure(_ provider: AIQuotaProvider, _ message: String) -> AIQuotaSnapshot {
        AIQuotaSnapshot(
            provider: provider, source: nil, updatedAt: nil,
            primary: nil, secondary: nil, tertiary: nil, extraWindows: [],
            account: nil, plan: nil, error: message
        )
    }

    private func left(of window: AIQuotaWindow?) -> Double? {
        guard let window else { return nil }
        if let left = window.leftPercent { return left }
        if let used = window.usedPercent { return 100 - used }
        return nil
    }

    /// The percent-left shown in the compact menu-bar title. Prefers the
    /// primary window, then secondary, then tertiary, then the lowest
    /// remaining per-model window (so the title surfaces the tightest
    /// limit for providers like Antigravity whose primary is null).
    var primaryLeftPercent: Double? {
        if let p = left(of: primary) { return p }
        if let s = left(of: secondary) { return s }
        if let t = left(of: tertiary) { return t }
        return extraWindows.compactMap(\.leftPercent).min()
    }

    private func used(of window: AIQuotaWindow?) -> Double? {
        guard let window else { return nil }
        if let used = window.usedPercent { return used }
        if let left = window.leftPercent { return 100 - left }
        return nil
    }

    /// The weekly (secondary) usage percent shown in the menu-bar title.
    /// Falls back to tertiary, then the busiest per-model window, then
    /// primary, so every provider surfaces something meaningful.
    var weeklyUsedPercent: Double? {
        if let s = used(of: secondary) { return s }
        if let t = used(of: tertiary) { return t }
        if let m = extraWindows.compactMap(\.usedPercent).max() { return m }
        return used(of: primary)
    }

    /// Remaining percent for the weekly window (drives threshold color).
    var weeklyLeftPercent: Double? {
        weeklyUsedPercent.map { 100 - $0 }
    }
}
