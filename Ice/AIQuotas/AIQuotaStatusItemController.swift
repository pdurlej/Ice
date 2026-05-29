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

    /// UserDefaults flag: set once we've moved the item to the leftmost
    /// visible slot (fire.9.7). Older builds forced position 0 (far right,
    /// right of Spotlight); this one-time migration relocates existing
    /// installs, after which manual drags are respected.
    private static let positionMigratedKey = "AIQuotasPositionLeftOfSystemV1"

    /// UserDefaults key holding Ice's own Visible control item position —
    /// the left edge of the always-visible zone. We read it to place AI
    /// Quotas just inside it. (We run inside Ice, so it's our own domain.)
    private static let visibleControlItemPositionKey =
        "NSStatusItem Preferred Position Ice.ControlItem.Visible"

    private var statusItem: NSStatusItem?
    private let logger = Logger(category: "AIQuota.StatusItem")

    private var preferredPositionKey: String {
        "NSStatusItem Preferred Position \(Self.autosaveName)"
    }

    /// Lazily creates the status item exactly once, reproducing Ice's
    /// control-item recipe so it lands (and stays) in the visible area.
    private func ensureStatusItem() -> NSStatusItem {
        if let statusItem { return statusItem }

        // STEP 1 — choose the preferred position BEFORE creation (setting
        // it afterward is a no-op). macOS places lower preferred positions
        // toward the trailing/right (visible) edge, higher ones toward the
        // leading/left edge.
        //
        // Goal: land AI Quotas as the LEFTMOST always-visible element, just
        // inside Ice's Visible control item (the "•••"), so it sits to the
        // LEFT of the system icons (Spotlight, Control Center, clock) yet
        // stays on-screen. Left of the Visible control item is Ice's wide
        // section divider, which pushes items off-screen — so this is as
        // far left as a visible item can go.
        let defaults = UserDefaults.standard
        let visiblePos = defaults.object(forKey: Self.visibleControlItemPositionKey) as? Double
        // Just inside the Visible control item. Fall back to 0 (guaranteed
        // visible, far right) only if Ice hasn't persisted its own position
        // yet — the self-heal below corrects it on a later launch.
        let target = visiblePos.map { $0 - 1 } ?? 0
        let current = defaults.object(forKey: preferredPositionKey) as? Double

        let needsPlacement: Bool
        if !defaults.bool(forKey: Self.positionMigratedKey) {
            needsPlacement = true                       // one-time migration
            defaults.set(true, forKey: Self.positionMigratedKey)
        } else if let current {
            // Re-place only if parked off-screen (left of the Visible
            // control item, behind Ice's divider). Otherwise respect the
            // user's manual placement so drags stick.
            needsPlacement = visiblePos.map { current > $0 } ?? false
        } else {
            needsPlacement = true                       // unset
        }
        if needsPlacement {
            defaults.set(target, forKey: preferredPositionKey)
            logger.debug("Set AI Quotas preferred position to \(target) (was \(String(describing: current)))")
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
