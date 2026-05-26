//
//  MenuBarStateManager.swift
//  MenuBarItemService
//
//  Server-side state manager for the MCP-extended XPC contract.
//
//  Phase G (fire.6) implementation status:
//    - listItems(section:)  — REAL impl, AX/Bridging-driven, no deps on
//      Ice main app target. Detects section by x-coordinate relative to
//      Ice's 3 control items (bundleID match com.jordanbaird.Ice).
//    - saveLayout(name:)    — REAL impl, snapshots current state to a
//      "MCPLayouts" dict in UserDefaults (Ice's suite if accessible, else
//      this service's own suite).
//    - moveItem / hideItem / showItem / applyLayout — return a friendly
//      "Coming in fire.7" message. Mutations need Option D (Ice.app hosts
//      MCP backend) for proper cross-process AX synchronization with
//      MenuBarItemManager.
//
//  Why fire.6 ships read-only: the XPC service runs in a different
//  process than Ice.app. Cross-process AX moves coordinated through
//  Ice's existing MenuBarItemManager singleton require either (a)
//  cross-target type sharing (heavy cascade through AppState) or (b)
//  Ice hosting its own XPC service. Both are tracked for fire.7. The
//  read path doesn't need either — AX queries work in any process with
//  Accessibility permission.
//

import Cocoa
import Foundation
import OSLog

final class MenuBarStateManager {
    /// The shared manager.
    static let shared = MenuBarStateManager()

    /// UserDefaults key under which named MCP layouts are persisted.
    /// Format: `[layoutName: [sectionRawValue: [{bundleID, position}]]]`.
    private static let layoutsKey = "MCPLayouts"

    /// Ice's main app bundle ID — used to identify Ice's control items
    /// in the menu bar (they sit at section boundaries).
    private static let iceBundleID = "com.jordanbaird.Ice"

    /// Ice's plist if accessible, else this service's own standard suite.
    /// fire.7 (Option D) unifies storage when Ice hosts the MCP backend
    /// directly — bridges read both locations during the migration.
    private var defaults: UserDefaults {
        UserDefaults(suiteName: Self.iceBundleID) ?? .standard
    }

    private init() {}

    // MARK: - Read

    /// Returns the list of menu bar items across ALL active displays,
    /// classified by section based on x-coordinate relative to Ice's
    /// per-display control items.
    ///
    /// - Parameter section: If non-nil, filter results to that section.
    ///
    /// fire.7: multi-display support added. Items are accumulated across
    /// displays, with positions numbered per-section globally (primary
    /// display first, then secondary displays in `CGGetActiveDisplayList`
    /// order). When a display has fewer than 3 Ice control items
    /// visible (Ice's hidden or always-hidden section is collapsed
    /// off-screen, or Ice isn't running on that display), items on that
    /// display get assigned to `.alwaysVisible` as a graceful fallback.
    func listItems(section: MenuBarItemService.ItemSection?) -> [MenuBarItemService.ItemInfo] {
        Logger.default.debug(
            "MenuBarStateManager.listItems(section: \(String(describing: section)))"
        )

        // 1. Enumerate menu bar item windows across all displays.
        let windowIDs = Bridging.getMenuBarWindowList(option: .itemsOnly)
        let allWindows = WindowInfo.createWindows(from: windowIDs)

        // 2. Iterate active displays (primary first per CGS convention).
        //    Per-display section detection means each display's Ice
        //    control items act as boundaries only for that display's
        //    items, never bleeding into another display's classification.
        let displays = Self.activeDisplayIDs()

        // Accumulate items per section across all displays. Items
        // discovered earlier (e.g. on primary display) come first in
        // each section's array, giving stable positions.
        var bucketed: [MenuBarItemService.ItemSection: [WindowInfo]] = [:]
        var totalSeen = 0
        var totalBucketed = 0

        for (displayIndex, displayID) in displays.enumerated() {
            let displayBounds = CGDisplayBounds(displayID)
            let displayWindows = allWindows.filter { window in
                displayBounds.contains(
                    CGPoint(x: window.bounds.midX, y: window.bounds.midY)
                )
            }
            totalSeen += displayWindows.count

            let (iceControls, otherItems) = displayWindows.splitByPredicate { window in
                window.owningApplication?.bundleIdentifier == Self.iceBundleID
            }

            let sortedControls = iceControls.sorted { $0.bounds.minX < $1.bounds.minX }

            guard sortedControls.count >= 3 else {
                // Per-display fallback: this display doesn't have Ice's
                // 3 control items visible (collapsed section / Ice off /
                // secondary display where Ice isn't placed). Report items
                // as alwaysVisible - the LLM still sees them.
                Logger.default.notice(
                    "Display \(displayIndex) (id=\(displayID)): \(sortedControls.count) Ice control items found, falling back to alwaysVisible classification"
                )
                bucketed[.alwaysVisible, default: []].append(
                    contentsOf: otherItems.sorted { $0.bounds.minX < $1.bounds.minX }
                )
                totalBucketed += otherItems.count
                continue
            }

            let alwaysHiddenBoundary = sortedControls[0].bounds.minX
            let hiddenBoundary = sortedControls[1].bounds.minX
            let visibleBoundary = sortedControls[2].bounds.minX

            // Classify each non-Ice item on this display by x-coordinate.
            //   Items right of visibleBoundary        -> .alwaysVisible
            //   Items between hidden and visible      -> .hidden
            //   Items between alwaysHidden and hidden -> .alwaysHidden
            //   Items left of alwaysHiddenBoundary    -> also .alwaysHidden
            //                                            (offscreen edge)
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
                totalBucketed += 1
            }
        }

        Logger.default.info(
            "listItems across \(displays.count) display(s): \(totalSeen) windows seen, \(totalBucketed) bucketed into sections"
        )

        // 3. Build ItemInfo list with per-section positions (numbered
        //    globally across all displays - primary display items get
        //    lower positions because they're accumulated first).
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

    /// Returns the IDs of all active displays, with the main display
    /// first. Wraps `CGGetActiveDisplayList` so callers don't have to
    /// deal with the two-call query-then-fill pattern.
    private static func activeDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            return []
        }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else {
            return []
        }
        // Hoist the main display to the front so its items are numbered
        // first in each section. Some users have their MacBook display
        // as secondary; we still want their primary screen to lead.
        let mainID = CGMainDisplayID()
        if let mainIndex = ids.firstIndex(of: mainID), mainIndex != 0 {
            ids.swapAt(0, mainIndex)
        }
        return ids
    }

    /// Builds a wire `ItemInfo` from a `WindowInfo`. Resolves bundle ID
    /// via SourcePIDCache (macOS 26 Control Center reparent aware) and
    /// falls back to `ownerPID` for older macOS.
    private func makeItemInfo(
        window: WindowInfo,
        section: MenuBarItemService.ItemSection,
        position: Int
    ) -> MenuBarItemService.ItemInfo {
        let resolvedPID = SourcePIDCache.shared.pid(for: window) ?? window.ownerPID
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

    // MARK: - Write (deferred to fire.7)

    /// Returns the friendly fire.7-deferral message. fire.7 implements
    /// real moves via Option D (Ice.app hosts MCP backend with direct
    /// access to MenuBarItemManager.shared).
    func moveItem(
        bundleID: String,
        toSection: MenuBarItemService.ItemSection,
        toIndex: Int?
    ) -> (success: Bool, message: String?) {
        Logger.default.debug(
            "MenuBarStateManager.moveItem(\(bundleID), to: \(toSection.rawValue), index: \(String(describing: toIndex))) — deferred"
        )
        return (
            false,
            "Write operations land in fire.7. fire.6 supports list_items and save_layout for inspection workflows."
        )
    }

    /// Convenience wrapper — currently deferred per `moveItem`.
    func hideItem(bundleID: String) -> (success: Bool, message: String?) {
        moveItem(bundleID: bundleID, toSection: .hidden, toIndex: nil)
    }

    /// Convenience wrapper — currently deferred per `moveItem`.
    func showItem(bundleID: String) -> (success: Bool, message: String?) {
        moveItem(bundleID: bundleID, toSection: .alwaysVisible, toIndex: nil)
    }

    /// Layout application deferred — needs the same write path that
    /// `moveItem` is waiting on.
    func applyLayout(name: String) -> (success: Bool, message: String?) {
        Logger.default.debug("MenuBarStateManager.applyLayout(\(name)) — deferred")
        return (
            false,
            "Layout application lands in fire.7 alongside the other write ops. fire.6 supports save_layout for snapshotting state."
        )
    }

    // MARK: - Save Layout (read-side write — implemented)

    /// Snapshots the current menu bar state as a named layout.
    ///
    /// - Format: `[layoutName: [sectionRawValue: [{bundleID, position}]]]`.
    /// - Returns: number of items captured, or nil on failure.
    func saveLayout(name: String) -> Int? {
        Logger.default.debug("MenuBarStateManager.saveLayout(\(name))")

        let items = listItems(section: nil)
        guard !items.isEmpty else {
            Logger.default.error("saveLayout: no items to snapshot — Ice may not be running")
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

        Logger.default.info("Saved layout '\(name)' with \(items.count) items")
        return items.count
    }
}

// MARK: - Sequence Helpers

private extension Sequence {
    /// Splits the sequence into two arrays based on a predicate.
    /// - Returns: `(matching, nonMatching)`.
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
