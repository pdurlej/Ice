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

    /// Returns the list of menu bar items on the primary display,
    /// classified by section based on x-coordinate relative to Ice's
    /// 3 control items.
    ///
    /// - Parameter section: If non-nil, filter results to that section.
    ///
    /// Multi-display support is deferred to fire.7 — items not on the
    /// primary display are excluded from results.
    func listItems(section: MenuBarItemService.ItemSection?) -> [MenuBarItemService.ItemInfo] {
        Logger.default.debug(
            "MenuBarStateManager.listItems(section: \(String(describing: section)))"
        )

        // 1. Enumerate menu bar item windows.
        let windowIDs = Bridging.getMenuBarWindowList(option: .itemsOnly)
        let allWindows = WindowInfo.createWindows(from: windowIDs)

        // 2. Filter to the primary display. fire.7 will expand this.
        let mainDisplay = CGMainDisplayID()
        let mainBounds = CGDisplayBounds(mainDisplay)
        let primaryWindows = allWindows.filter { window in
            mainBounds.contains(
                CGPoint(x: window.bounds.midX, y: window.bounds.midY)
            )
        }

        // 3. Split Ice's control items from the rest.
        let (iceControls, otherItems) = primaryWindows.splitByPredicate { window in
            window.owningApplication?.bundleIdentifier == Self.iceBundleID
        }

        // 4. Ice creates 3 control items per display (one per section).
        //    Sorted ascending by x, they mark the LEFT edges of the
        //    alwaysHidden / hidden / visible sections respectively.
        //
        //    If we can't find them (Ice isn't running, or fewer than 3
        //    are placed), gracefully degrade by reporting all items as
        //    .alwaysVisible. Less precise but still useful — the LLM
        //    sees what's in the menu bar even when Ice is off.
        let sortedControls = iceControls.sorted { $0.bounds.minX < $1.bounds.minX }
        guard sortedControls.count >= 3 else {
            Logger.default.notice(
                "Found \(sortedControls.count) Ice control items on primary display (expected 3) — reporting all items as alwaysVisible"
            )
            let fallback = otherItems
                .sorted { $0.bounds.minX < $1.bounds.minX }
                .enumerated()
                .map { index, window in
                    makeItemInfo(window: window, section: .alwaysVisible, position: index)
                }
            if let section {
                return fallback.filter { $0.section == section }
            }
            return fallback
        }

        let alwaysHiddenBoundary = sortedControls[0].bounds.minX
        let hiddenBoundary = sortedControls[1].bounds.minX
        let visibleBoundary = sortedControls[2].bounds.minX

        // 5. Classify each non-Ice item by x-coordinate.
        //    Items right of visibleBoundary       → .alwaysVisible
        //    Items between hidden and visible     → .hidden
        //    Items between alwaysHidden and hidden → .alwaysHidden
        //    Items left of alwaysHiddenBoundary    → also .alwaysHidden
        //                                           (offscreen edge)
        var bucketed: [MenuBarItemService.ItemSection: [WindowInfo]] = [:]
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

        // 6. Build ItemInfo list with per-section positions.
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
