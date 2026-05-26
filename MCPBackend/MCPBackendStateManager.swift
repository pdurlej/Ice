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
        // Note: no SourcePIDCache here (it lives in MenuBarItemService.xpc).
        // ownerPID is the macOS-25-and-older window owner; on macOS 26
        // Control Center reparents most items so ownerPID may all be
        // Control Center's PID. bundleID then ends up as
        // "com.apple.controlcenter" for everything. Not ideal but
        // honest - W2 decides whether to share SourcePIDCache.
        let app = NSRunningApplication(processIdentifier: window.ownerPID)
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

    // MARK: - Write (W2 will implement)

    func moveItem(
        bundleID: String,
        toSection: MenuBarItemService.ItemSection,
        toIndex: Int?
    ) async -> (success: Bool, message: String?) {
        logger.debug(
            "moveItem(\(bundleID), to: \(toSection.rawValue), index: \(String(describing: toIndex))) - W2 stub"
        )
        return (
            false,
            "Write operations land in fire.8 W2 (lean port of CGEvent drag logic). MCPBackend service scaffold ships first."
        )
    }

    func hideItem(bundleID: String) async -> (success: Bool, message: String?) {
        await moveItem(bundleID: bundleID, toSection: .hidden, toIndex: nil)
    }

    func showItem(bundleID: String) async -> (success: Bool, message: String?) {
        await moveItem(bundleID: bundleID, toSection: .alwaysVisible, toIndex: nil)
    }

    func applyLayout(name: String) async -> (success: Bool, message: String?) {
        logger.debug("applyLayout(\(name)) - W2 stub")
        return (
            false,
            "Layout application requires write ops (fire.8 W2). Currently lists / saves layouts only."
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
