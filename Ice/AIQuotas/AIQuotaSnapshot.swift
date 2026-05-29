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
    /// Account label (email) if available.
    let account: String?
    /// Plan / login method if available (e.g. "pro").
    let plan: String?
    /// Non-nil if the fetch failed; the snapshot is otherwise empty.
    let error: String?

    /// True when the snapshot carries at least one usable window and no
    /// error.
    var isUsable: Bool {
        error == nil && (primary != nil || secondary != nil)
    }

    /// Convenience: an error-only snapshot for a provider.
    static func failure(_ provider: AIQuotaProvider, _ message: String) -> AIQuotaSnapshot {
        AIQuotaSnapshot(
            provider: provider, source: nil, updatedAt: nil,
            primary: nil, secondary: nil, account: nil, plan: nil,
            error: message
        )
    }

    /// The percent-left for the primary window, used for the compact
    /// menu-bar title. Falls back to deriving from usedPercent.
    var primaryLeftPercent: Double? {
        guard let primary else { return nil }
        if let left = primary.leftPercent { return left }
        if let used = primary.usedPercent { return 100 - used }
        return nil
    }
}
