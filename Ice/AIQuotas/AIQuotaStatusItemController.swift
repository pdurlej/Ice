//
//  AIQuotaStatusItemController.swift
//  Ice
//
//  Owns the single AI Quotas menu-bar item.
//
//  ARCHITECTURE (rebuilt from first principles, fire.9.4)
//  ------------------------------------------------------
//  Ice is a menu-bar manager: its entire job is hiding and relocating
//  third-party NSStatusItems. A naive AI Quotas NSStatusItem therefore
//  gets swept into Ice's hidden sections and parked off-screen amid
//  Ice's very wide (10 000pt) section-divider items — there is no stable
//  "preferred position" that survives. (CodexBar hit the same wall; it's
//  architectural, not a placement bug.)
//
//  The only menu-bar elements that stay reliably visible under Ice are
//  Ice's OWN control items, and they work for two concrete reasons,
//  both of which we reproduce here:
//
//   1. They force a LOW NSStatusItem "Preferred Position" (0) into
//      UserDefaults BEFORE the status item is created, so macOS places
//      them at the trailing/visible edge instead of leftmost (hidden).
//      See ControlItem.preflightSetup. Setting the position AFTER
//      creation does not work.
//   2. Their tag is in MenuBarItemTag.controlItems, so the item manager
//      never caches, classifies, or moves them as third-party items.
//      We register `aiQuotasControlItem` there and name this item
//      "Ice.ControlItem.AIQuotas" so its window title matches that tag.
//
//  Net effect: the AI Quotas item is a first-class, always-visible
//  Ice-owned element — not a third-party item fighting Ice for a slot.
//

import AppKit
import OSLog

@MainActor
final class AIQuotaStatusItemController {
    /// Autosave name == the tag title in MenuBarItemTag.aiQuotasControlItem.
    /// The "Ice.ControlItem." prefix keeps it grouped with Ice's own
    /// control items and makes its window title recognizable.
    static let autosaveName = "Ice.ControlItem.AIQuotas"

    private var statusItem: NSStatusItem?
    private let logger = Logger(category: "AIQuota.StatusItem")

    private var preferredPositionKey: String {
        "NSStatusItem Preferred Position \(Self.autosaveName)"
    }

    /// Lazily creates the status item exactly once, reproducing Ice's
    /// control-item recipe so it lands (and stays) in the visible area.
    private func ensureStatusItem() -> NSStatusItem {
        if let statusItem { return statusItem }

        // STEP 1 — force a low preferred position BEFORE creation. macOS
        // places items with a lower preferred position toward the
        // trailing (visible, clock-adjacent) edge. Ice's visible control
        // item uses 0 for exactly this reason. We set it if unset or if
        // a previous build left it parked far left (a large value).
        let defaults = UserDefaults.standard
        let current = defaults.object(forKey: preferredPositionKey) as? Double
        if current == nil || (current ?? 0) > 100 {
            defaults.set(0.0, forKey: preferredPositionKey)
            logger.debug("Forced AI Quotas preferred position to 0 (was \(String(describing: current)))")
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = Self.autosaveName
        item.button?.setAccessibilityIdentifier("Fire.AIQuotas.StatusItem")
        item.button?.toolTip = "AI Quotas"
        // Stamp the window title so the item manager's control-item tag
        // match (MenuBarItemTag.aiQuotasControlItem) is reliable even if
        // macOS's autosave-derived title ever drifts.
        item.button?.window?.title = Self.autosaveName

        statusItem = item
        logger.debug("Created AI Quotas status item")
        return item
    }

    /// Shows the item (creating it if needed) and updates its
    /// rich (icon + percent) title and menu.
    func show(attributedTitle: NSAttributedString, menu: NSMenu) {
        let item = ensureStatusItem()
        item.isVisible = true
        if let button = item.button {
            button.attributedTitle = attributedTitle
            // Let the icon attachments render at full color rather than
            // being flattened to a template tint.
            button.image = nil
        }
        item.menu = menu
    }

    /// Hides the item without destroying it (preserves position).
    func hide() {
        statusItem?.isVisible = false
    }
}
