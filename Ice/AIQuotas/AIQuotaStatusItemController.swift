//
//  AIQuotaStatusItemController.swift
//  Ice
//
//  Owns the single combined AI Quotas NSStatusItem. The status item is
//  created once and never recreated during refresh — only its title and
//  menu are updated. When disabled it is hidden (isVisible = false), not
//  destroyed, so its menu-bar position is preserved.
//

import AppKit
import OSLog

@MainActor
final class AIQuotaStatusItemController {
    /// Stable autosave name so macOS remembers the item's position.
    static let autosaveName = "Fire.AIQuotas.Combined"

    private var statusItem: NSStatusItem?
    private let logger = Logger(category: "AIQuota.StatusItem")

    /// Lazily creates the status item exactly once.
    private func ensureStatusItem() -> NSStatusItem {
        if let statusItem { return statusItem }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = Self.autosaveName
        item.button?.setAccessibilityIdentifier("Fire.AIQuotas.StatusItem")
        item.button?.toolTip = "AI Quotas"
        statusItem = item
        logger.debug("Created AI Quotas status item")
        return item
    }

    /// Shows the item (creating it if needed) and updates its title.
    func show(title: String, menu: NSMenu) {
        let item = ensureStatusItem()
        item.isVisible = true
        item.button?.title = title
        item.menu = menu
    }

    /// Updates only the title and menu of an already-visible item.
    func update(title: String, menu: NSMenu) {
        guard let statusItem else { return }
        statusItem.button?.title = title
        statusItem.menu = menu
    }

    /// Hides the item without destroying it (preserves position).
    func hide() {
        statusItem?.isVisible = false
    }
}
