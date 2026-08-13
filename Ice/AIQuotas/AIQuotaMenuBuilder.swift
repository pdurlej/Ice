//
//  AIQuotaMenuBuilder.swift
//  Ice
//
//  Builds the combined menu-bar title string and the dropdown NSMenu
//  from per-provider snapshots. Pure formatting — no I/O, no state — so
//  the title formatter is unit-testable.
//

import AppKit

@MainActor
enum AIQuotaMenuBuilder {
    // MARK: Title

    /// Builds the compact menu-bar title, e.g. "AI Cx73 Cl88 Gm42 Ol100"
    /// (or without the "AI " prefix in compact mode). Unknown / errored
    /// providers render as "Cx?".
    static func title(
        for providers: [AIQuotaProvider],
        snapshots: [AIQuotaProvider: AIQuotaSnapshot],
        compact: Bool
    ) -> String {
        let parts = providers.map { provider -> String in
            let label = provider.shortLabel
            guard
                let snapshot = snapshots[provider],
                snapshot.isUsable,
                let left = snapshot.primaryLeftPercent
            else {
                return "\(label)?"
            }
            return "\(label)\(Int(left.rounded()))"
        }
        let body = parts.joined(separator: " ")
        return compact ? body : "AI \(body)"
    }

    /// Builds the rich menu-bar title: each provider's brand icon
    /// followed by its weekly *remaining* percent, e.g. [Cx] 79% [Cl] 62% …
    /// — i.e. how much headroom is still available, not how much was
    /// consumed. The percent is color-coded by that headroom (orange
    /// < 20% left, red < 10% left), so a small red number reads as
    /// "almost out". Providers without a brand icon fall back to their
    /// two-letter short label.
    static func attributedTitle(
        for providers: [AIQuotaProvider],
        snapshots: [AIQuotaProvider: AIQuotaSnapshot]
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .small))

        for (index, provider) in providers.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "  "))
            }

            // Brand icon (or short-label fallback).
            if let icon = AIQuotaProviderIcon.image(for: provider) {
                let attachment = NSTextAttachment()
                attachment.image = icon
                // Nudge down so the icon centers on the text baseline.
                attachment.bounds = CGRect(
                    x: 0,
                    y: (font.capHeight - icon.size.height) / 2,
                    width: icon.size.width,
                    height: icon.size.height
                )
                result.append(NSAttributedString(attachment: attachment))
            } else {
                result.append(NSAttributedString(
                    string: provider.shortLabel,
                    attributes: [.font: font, .foregroundColor: NSColor.labelColor]
                ))
            }

            // Weekly *remaining* percent, color-coded by that same
            // headroom (low = running out = red). Shows what's still
            // available rather than what was consumed.
            let snapshot = snapshots[provider]
            let usageText: String
            let color: NSColor
            if let snapshot, snapshot.isUsable, let left = snapshot.weeklyLeftPercent {
                usageText = "\u{2009}\(Int(left.rounded()))%"
                color = left < 10 ? .systemRed : (left < 20 ? .systemOrange : .labelColor)
            } else {
                usageText = "\u{2009}?"
                color = .secondaryLabelColor
            }
            result.append(NSAttributedString(
                string: usageText,
                attributes: [.font: font, .foregroundColor: color]
            ))
        }
        return result
    }

    // MARK: Menu

    static func menu(
        for providers: [AIQuotaProvider],
        snapshots: [AIQuotaProvider: AIQuotaSnapshot],
        backendAvailable: Bool,
        target: AnyObject,
        refreshAction: Selector,
        openSettingsAction: Selector,
        installCLIAction: Selector
    ) -> NSMenu {
        let menu = NSMenu()

        let header = NSMenuItem(title: "AI Quotas", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        for provider in providers {
            addProviderSection(
                to: menu, provider: provider, snapshot: snapshots[provider]
            )
            menu.addItem(.separator())
        }

        let refresh = NSMenuItem(title: "Refresh Now", action: refreshAction, keyEquivalent: "r")
        refresh.target = target
        menu.addItem(refresh)

        let settings = NSMenuItem(title: "Open AI Quotas Settings…", action: openSettingsAction, keyEquivalent: "")
        settings.target = target
        menu.addItem(settings)

        if !backendAvailable {
            let install = NSMenuItem(title: "Install / Configure CodexBar CLI…", action: installCLIAction, keyEquivalent: "")
            install.target = target
            menu.addItem(install)
        }

        return menu
    }

    private static func addProviderSection(
        to menu: NSMenu, provider: AIQuotaProvider, snapshot: AIQuotaSnapshot?
    ) {
        let name = NSMenuItem(title: provider.displayName, action: nil, keyEquivalent: "")
        name.isEnabled = false
        menu.addItem(name)

        func detail(_ text: String) {
            let item = NSMenuItem(title: "   \(text)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        guard let snapshot else {
            detail("No data yet")
            return
        }

        if let error = snapshot.error {
            detail("⚠︎ \(error)")
            return
        }

        if let primary = snapshot.primary {
            detail("\(windowLabel(primary)): \(leftString(primary)) left")
            if let resets = primary.resetsAt {
                detail("Resets: \(Self.resetFormatter.string(from: resets))")
            }
        }
        if let secondary = snapshot.secondary {
            detail("\(windowLabel(secondary)): \(leftString(secondary)) left")
            if let resets = secondary.resetsAt {
                detail("Resets: \(Self.resetFormatter.string(from: resets))")
            }
        }
        if let tertiary = snapshot.tertiary {
            detail("\(windowLabel(tertiary)): \(leftString(tertiary)) left")
        }
        // Per-model windows (e.g. Antigravity's Gemini models). Show the
        // ones that have data; keep it readable by capping the list.
        let extras = snapshot.extraWindows.filter { $0.usedPercent != nil }
        for extra in extras.prefix(12) {
            let left = extra.leftPercent.map { "\(Int($0.rounded()))%" } ?? "?"
            detail("\(extra.title): \(left) left")
        }
        if extras.count > 12 {
            detail("… and \(extras.count - 12) more")
        }
        if let source = snapshot.source {
            detail("Source: \(source)")
        }
        if let account = snapshot.account {
            detail("Account: \(account)")
        }
        if let updated = snapshot.updatedAt {
            detail("Updated: \(Self.updatedFormatter.string(from: updated))")
        }
    }

    private static func leftString(_ window: AIQuotaWindow) -> String {
        if let left = window.leftPercent {
            return "\(Int(left.rounded()))%"
        }
        if let used = window.usedPercent {
            return "\(Int((100 - used).rounded()))%"
        }
        return "?"
    }

    /// Friendly window label from its length in minutes.
    private static func windowLabel(_ window: AIQuotaWindow) -> String {
        guard let minutes = window.windowMinutes else {
            return window.kind == .primary ? "Session" : "Window"
        }
        switch minutes {
        case 300: return "5h/session"
        case 10080: return "Weekly"
        case let m where m % 1440 == 0: return "\(m / 1440)d"
        case let m where m % 60 == 0: return "\(m / 60)h"
        default: return "\(minutes)m"
        }
    }

    private static let resetFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.doesRelativeDateFormatting = true
        return f
    }()

    private static let updatedFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()
}
