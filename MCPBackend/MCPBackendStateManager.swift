//
//  MCPBackendStateManager.swift
//  MCPBackend
//
//  Server-side state manager for the MCP backend XPC service.
//
//  W1 scope (this commit, paired with target scaffold):
//    - listItems(section:) - REAL, multi-display. Ported from
//      MenuBarItemService/MenuBarStateManager.swift's fire.7 impl with
//      the addition that this service uses ownerPID directly (no
//      SourcePIDCache available - that lives in MenuBarItemService.xpc
//      target). bundleID resolution may be less accurate on macOS 26
//      Control Center reparent cases; W2 decides whether to share
//      SourcePIDCache or accept ownerPID-only.
//    - saveLayout(name:) - REAL, writes to Ice's plist (suite name
//      com.jordanbaird.Ice so both old and new clients see the same
//      MCPLayouts dict).
//    - listLayouts() - REAL, reads from the same plist.
//    - moveItem / hideItem / showItem / applyLayout - STUB returning
//      "W2 placeholder" message. W2 ports the lean CGEvent posting
//      logic from Ice's MenuBarItemManager into a standalone helper
//      here. ~600-800 lines of careful porting.
//

import Cocoa
import Foundation
import OSLog

final class MCPBackendStateManager {
    /// The shared manager.
    static let shared = MCPBackendStateManager()

    /// UserDefaults key under which named MCP layouts are persisted.
    /// Same key as the legacy fire.6/fire.7 MenuBarStateManager so
    /// layouts saved in either service show up in the other.
    private static let layoutsKey = "MCPLayouts"

    /// Ice's main app bundle ID - used to identify Ice's control items
    /// in the menu bar (they sit at section boundaries) and as the
    /// UserDefaults suite for layout persistence.
    private static let iceBundleID = "com.jordanbaird.Ice"

    /// Ice's plist if accessible, else this service's own standard
    /// suite. Same fallback as MenuBarStateManager.
    private var defaults: UserDefaults {
        UserDefaults(suiteName: Self.iceBundleID) ?? .standard
    }

    private let logger = Logger(category: "MCPBackend.StateManager")

    private init() {}

    // MARK: - Read

    /// Returns the list of menu bar items across all active displays.
    /// fire.7-equivalent algorithm: iterate displays, find Ice control
    /// items per-display, bucket items by x-coord into sections.
    func listItems(section: MenuBarItemService.ItemSection?) async -> [MenuBarItemService.ItemInfo] {
        logger.debug("listItems(section: \(String(describing: section)))")

        let windowIDs = Bridging.getMenuBarWindowList(option: .itemsOnly)
        let allWindows = WindowInfo.createWindows(from: windowIDs)

        let displays = Self.activeDisplayIDs()

        var bucketed: [MenuBarItemService.ItemSection: [WindowInfo]] = [:]

        for (displayIndex, displayID) in displays.enumerated() {
            let displayBounds = CGDisplayBounds(displayID)
            let displayWindows = allWindows.filter { window in
                displayBounds.contains(CGPoint(x: window.bounds.midX, y: window.bounds.midY))
            }

            let (iceControls, otherItems) = displayWindows.splitByPredicate { window in
                window.owningApplication?.bundleIdentifier == Self.iceBundleID
            }

            let sortedControls = iceControls.sorted { $0.bounds.minX < $1.bounds.minX }
            guard sortedControls.count >= 3 else {
                logger.notice(
                    "Display \(displayIndex) (id=\(displayID)): \(sortedControls.count) Ice control items found, fallback to alwaysVisible"
                )
                bucketed[.alwaysVisible, default: []].append(
                    contentsOf: otherItems.sorted { $0.bounds.minX < $1.bounds.minX }
                )
                continue
            }

            let alwaysHiddenBoundary = sortedControls[0].bounds.minX
            let hiddenBoundary = sortedControls[1].bounds.minX
            let visibleBoundary = sortedControls[2].bounds.minX

            for window in otherItems.sorted(by: { $0.bounds.minX < $1.bounds.minX }) {
                let x = window.bounds.minX
                let assigned: MenuBarItemService.ItemSection
                if x > visibleBoundary {
                    assigned = .alwaysVisible
                } else if x > hiddenBoundary {
                    assigned = .hidden
                } else {
                    assigned = .alwaysHidden
                }
                bucketed[assigned, default: []].append(window)
            }
        }

        var results: [MenuBarItemService.ItemInfo] = []
        for assigned in MenuBarItemService.ItemSection.allCases {
            let windows = bucketed[assigned] ?? []
            for (position, window) in windows.enumerated() {
                results.append(makeItemInfo(window: window, section: assigned, position: position))
            }
        }

        if let section {
            return results.filter { $0.section == section }
        }
        return results
    }

    private func makeItemInfo(
        window: WindowInfo,
        section: MenuBarItemService.ItemSection,
        position: Int
    ) -> MenuBarItemService.ItemInfo {
        // Smoke test discovered the bundleIDs collapsed to
        // com.apple.controlcenter for every item on macOS 26 — that's
        // because ownerPID gets reparented to Control Center by the
        // system. Resolve the source PID via the AX cache (same
        // mechanism MenuBarItemService.xpc uses for the sourcePID
        // XPC handshake; promoted to Shared/ so both .xpc services
        // share the logic, though each process keeps its own cache).
        let sourcePID = SourcePIDCache.shared.pid(for: window)
        let resolvedPID = sourcePID ?? window.ownerPID
        let app = NSRunningApplication(processIdentifier: resolvedPID)
        let bundleID = app?.bundleIdentifier ?? window.ownerName ?? "unknown"
        let displayName = app?.localizedName ?? window.title ?? window.ownerName

        return MenuBarItemService.ItemInfo(
            bundleID: bundleID,
            displayName: displayName,
            windowID: window.windowID,
            section: section,
            position: position,
            isOnScreen: window.isOnScreen
        )
    }

    /// Returns the IDs of all active displays, with the main display
    /// first. Same helper as MenuBarItemService/MenuBarStateManager.
    private static func activeDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            return []
        }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else {
            return []
        }
        let mainID = CGMainDisplayID()
        if let mainIndex = ids.firstIndex(of: mainID), mainIndex != 0 {
            ids.swapAt(0, mainIndex)
        }
        return ids
    }

    // MARK: - Write (W2 - real implementation via Mover)

    /// Moves the item with the given bundle ID to the target section.
    ///
    /// Implementation: find the source item in the menu bar, find Ice's
    /// control item that bounds the destination section, dispatch a
    /// `Mover.MoveDestination.rightOfItem(controlItem)` so the moved item
    /// lands just inside the target section. `toIndex` is currently
    /// ignored - the moved item lands at the start of the target section.
    /// Refinement to land at a specific intra-section index is a future
    /// pass (would require iterating siblings and picking left/right of
    /// the right neighbour).
    func moveItem(
        bundleID: String,
        toSection: MenuBarItemService.ItemSection,
        toIndex: Int?
    ) async -> (success: Bool, message: String?) {
        logger.debug(
            "moveItem(\(bundleID), to: \(toSection.rawValue), index: \(String(describing: toIndex)))"
        )

        // Find the source window for the bundle ID across all displays.
        let windowIDs = Bridging.getMenuBarWindowList(option: .itemsOnly)
        let allWindows = WindowInfo.createWindows(from: windowIDs)
        guard let sourceWindow = findWindow(for: bundleID, in: allWindows) else {
            return (false, "Item with bundle ID '\(bundleID)' not found in menu bar")
        }

        // Find Ice control items for the same display as the source item.
        // Falls back to main display if the source's display detection
        // fails (e.g. item just off the menu bar's drawn region).
        let displayID = displayContaining(sourceWindow.bounds) ?? CGMainDisplayID()
        guard let controls = findIceControlItems(displayID: displayID, in: allWindows) else {
            return (false, "Could not locate Ice's 3 control items on the current display - is Ice running with 'Hidden' section enabled?")
        }

        // Pick the control item that bounds the target section.
        // See section detection algorithm in listItems above:
        //   .alwaysHidden lies between controls[0] and controls[1]
        //   .hidden       lies between controls[1] and controls[2]
        //   .alwaysVisible lies to the right of controls[2]
        // Posting "rightOf(controls[N])" lands the moved item just inside
        // the target section's leftmost position.
        let boundaryControl: WindowInfo
        switch toSection {
        case .alwaysHidden: boundaryControl = controls[0]
        case .hidden:       boundaryControl = controls[1]
        case .alwaysVisible: boundaryControl = controls[2]
        }

        let moveItem = makeMoveItem(window: sourceWindow, displayName: bundleID)
        let targetItem = makeMoveItem(window: boundaryControl, displayName: "IceControl[\(toSection.rawValue)]")

        do {
            try await Mover.shared.move(
                item: moveItem,
                to: .rightOfItem(targetItem)
            )
            logger.info("moveItem succeeded for \(bundleID) → \(toSection.rawValue)")
            return (true, nil)
        } catch {
            logger.error("moveItem failed for \(bundleID): \(error)")
            return (false, "\(error)")
        }
    }

    func hideItem(bundleID: String) async -> (success: Bool, message: String?) {
        await moveItem(bundleID: bundleID, toSection: .hidden, toIndex: nil)
    }

    func showItem(bundleID: String) async -> (success: Bool, message: String?) {
        await moveItem(bundleID: bundleID, toSection: .alwaysVisible, toIndex: nil)
    }

    /// Applies a previously saved layout by replaying each item's
    /// recorded section assignment. Items not currently in the menu bar
    /// are skipped silently. First failure aborts and returns the
    /// partial state (rolling back would need the undo ring buffer,
    /// which lands in fire.8 W5 polish).
    func applyLayout(name: String) async -> (success: Bool, message: String?) {
        logger.debug("applyLayout(\(name))")

        guard
            let allLayouts = defaults.dictionary(forKey: Self.layoutsKey),
            let layout = allLayouts[name] as? [String: [[String: Any]]]
        else {
            return (false, "Layout '\(name)' not found")
        }

        // Replay order: alwaysHidden first (leftmost), then hidden, then
        // alwaysVisible. This minimises cascade re-positioning - if we
        // moved an alwaysVisible item first, then later moved an
        // alwaysHidden item, the alwaysVisible's index could shift.
        let replayOrder: [MenuBarItemService.ItemSection] = [
            .alwaysHidden, .hidden, .alwaysVisible,
        ]
        var moved = 0
        var skipped = 0
        for section in replayOrder {
            guard let entries = layout[section.rawValue] else { continue }
            // Within each section, preserve the position order.
            let sorted = entries.sorted { a, b in
                (a["position"] as? Int ?? 0) < (b["position"] as? Int ?? 0)
            }
            for entry in sorted {
                guard let bundleID = entry["bundleID"] as? String else { continue }
                let result = await moveItem(
                    bundleID: bundleID, toSection: section, toIndex: nil
                )
                if result.success {
                    moved += 1
                } else if let msg = result.message,
                          msg.contains("not found in menu bar") {
                    skipped += 1
                    logger.debug("applyLayout skipping absent item \(bundleID)")
                } else {
                    return (false, "Failed at \(bundleID) → \(section.rawValue): \(result.message ?? "unknown")")
                }
            }
        }
        return (true, "Applied layout '\(name)': moved \(moved) items, skipped \(skipped) absent")
    }

    // MARK: - W2 helpers

    /// Finds the menu bar window whose owning or source app has the
    /// given bundle ID. Skips Ice's own control items (which all share
    /// the Ice bundle ID and would confuse a "hide Ice" request).
    /// Checks both ownerPID (pre-macOS 26 / non-Control-Center items)
    /// and sourcePID via SourcePIDCache (macOS 26 Control Center
    /// reparented items).
    private func findWindow(
        for bundleID: String, in windows: [WindowInfo]
    ) -> WindowInfo? {
        guard bundleID != Self.iceBundleID else {
            return nil
        }
        return windows.first { window in
            // Try ownerPID first (cheap).
            if let owner = NSRunningApplication(processIdentifier: window.ownerPID),
               owner.bundleIdentifier == bundleID {
                return true
            }
            // Fall back to sourcePID (AX scan).
            if let sourcePID = SourcePIDCache.shared.pid(for: window),
               let source = NSRunningApplication(processIdentifier: sourcePID),
               source.bundleIdentifier == bundleID {
                return true
            }
            return false
        }
    }

    /// Finds Ice's 3 control items on the given display, sorted by X
    /// position (leftmost first). Returns nil if fewer than 3 are
    /// visible - that typically means Ice isn't running or all of
    /// alwaysHidden + hidden are collapsed off-screen.
    private func findIceControlItems(
        displayID: CGDirectDisplayID,
        in windows: [WindowInfo]
    ) -> [WindowInfo]? {
        let displayBounds = CGDisplayBounds(displayID)
        let iceControls = windows.filter { window in
            window.owningApplication?.bundleIdentifier == Self.iceBundleID &&
            displayBounds.contains(CGPoint(x: window.bounds.midX, y: window.bounds.midY))
        }
        let sorted = iceControls.sorted { $0.bounds.minX < $1.bounds.minX }
        guard sorted.count >= 3 else { return nil }
        return Array(sorted.prefix(3))
    }

    /// Returns the active display whose bounds contain the given
    /// rectangle's midpoint, or nil if no active display contains it.
    private func displayContaining(_ rect: CGRect) -> CGDirectDisplayID? {
        let mid = CGPoint(x: rect.midX, y: rect.midY)
        for displayID in Self.activeDisplayIDs() {
            if CGDisplayBounds(displayID).contains(mid) {
                return displayID
            }
        }
        return nil
    }

    /// Builds a Mover.MoveItem snapshot from a WindowInfo. Resolves
    /// sourcePID via SourcePIDCache so Mover can target the original
    /// creating process (Control Center on macOS 26) rather than the
    /// reparented owner.
    private func makeMoveItem(
        window: WindowInfo, displayName: String
    ) -> Mover.MoveItem {
        let sourcePID = SourcePIDCache.shared.pid(for: window)
        let ownerApp = NSRunningApplication(processIdentifier: window.ownerPID)
        let isBento = ownerApp?.bundleIdentifier == "com.apple.controlcenter"
        return Mover.MoveItem(
            windowID: window.windowID,
            ownerPID: window.ownerPID,
            sourcePID: sourcePID,
            bounds: window.bounds,
            isBentoBox: isBento,
            displayName: displayName
        )
    }

    // MARK: - Save Layout / List Layouts (read-side write - implemented)

    func saveLayout(name: String) async -> Int? {
        logger.debug("saveLayout(\(name))")

        let items = await listItems(section: nil)
        guard !items.isEmpty else {
            logger.error("saveLayout: no items to snapshot - Ice may not be running")
            return nil
        }

        var snapshot: [String: [[String: Any]]] = [:]
        for item in items {
            var sectionEntries = snapshot[item.section.rawValue, default: []]
            sectionEntries.append([
                "bundleID": item.bundleID,
                "position": item.position,
                "displayName": item.displayName ?? "",
            ])
            snapshot[item.section.rawValue] = sectionEntries
        }

        var allLayouts: [String: Any] = defaults.dictionary(forKey: Self.layoutsKey) ?? [:]
        allLayouts[name] = snapshot
        defaults.set(allLayouts, forKey: Self.layoutsKey)

        logger.info("Saved layout '\(name)' with \(items.count) items")
        return items.count
    }

    /// Returns the names of all saved layouts, in stable alphabetical
    /// order. Reads from the same MCPLayouts dict that
    /// MenuBarItemService.MenuBarStateManager wrote to in fire.7.1.
    func listLayouts() -> [String] {
        logger.debug("listLayouts()")
        let layouts = defaults.dictionary(forKey: Self.layoutsKey) ?? [:]
        return layouts.keys.sorted()
    }
}

// MARK: - Sequence Helpers

private extension Sequence {
    /// Splits the sequence into two arrays based on a predicate.
    func splitByPredicate(_ predicate: (Element) -> Bool) -> (matching: [Element], nonMatching: [Element]) {
        var matching: [Element] = []
        var nonMatching: [Element] = []
        for element in self {
            if predicate(element) {
                matching.append(element)
            } else {
                nonMatching.append(element)
            }
        }
        return (matching, nonMatching)
    }
}
