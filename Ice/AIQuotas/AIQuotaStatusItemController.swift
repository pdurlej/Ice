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

        // Reset a stale autosaved position before creating. If Ice (or a
        // prior build that didn't exclude this item) pushed it into a
        // hidden section, macOS persisted a far-left "Preferred Position"
        // and the item would re-appear off-screen. Clearing the key lets
        // macOS place it fresh in the visible status area. Ice's
        // isValidForCaching now excludes it, so it won't be pushed again.
        Self.resetStaleAutosavePositionIfNeeded()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = Self.autosaveName
        item.button?.setAccessibilityIdentifier("Fire.AIQuotas.StatusItem")
        item.button?.toolTip = "AI Quotas"
        // Stamp the window title so Ice's item manager can recognize this
        // as a Fire-owned, non-managed item (see isValidForCaching).
        item.button?.window?.title = Self.autosaveName
        statusItem = item
        logger.debug("Created AI Quotas status item")
        return item
    }

    /// The macOS-persisted preferred-position values for Ice's three
    /// control items cluster well below ~7000; a value far above that
    /// means the AI Quotas item was parked off-screen left. If so, drop
    /// the key so the item is re-placed in the visible area.
    private static func resetStaleAutosavePositionIfNeeded() {
        let key = "NSStatusItem Preferred Position \(autosaveName)"
        let pos = UserDefaults.standard.object(forKey: key) as? Double
        if let pos, pos > 8000 {
            UserDefaults.standard.removeObject(forKey: key)
        }
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
