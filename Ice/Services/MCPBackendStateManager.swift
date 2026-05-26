//
//  MCPBackendStateManager.swift
//  Ice
//
//  In-process state manager for the MCP backend. Runs inside the Ice
//  main app (NOT inside MenuBarItemService.xpc), so it has direct
//  access to the populated `MenuBarItemManager.itemCache` and the
//  AX-driven `move(item:to:)` path that the Layout settings UI uses.
//  Sharing that implementation is intentional: avoids two divergent
//  move pipelines.
//
//  Wire types (`ItemInfo`, `ItemSection`) come from
//  `Shared/Services/MenuBarItemService.swift`. Internal Ice types
//  (`MenuBarItem`, `MenuBarItemManager`, `MenuBarSection`, `MoveDestination`)
//  are local to the Ice target.
//
//  Lifecycle: `configure(itemManager:)` is called from AppDelegate at
//  launch (after AppState setup populates the cache). Then
//  `MCPBackend.shared.activate()` registers the XPC listener that
//  bridges incoming MCP tool calls into these methods.
//
//  Originally written by Worker B in the Wave 2 swarmheart dispatch
//  (saved as `MenuBarItemService/MenuBarStateManager.swift.proposal.phase3`).
//  Promoted here for Option D - the cross-target refactor turned out
//  to be heavier than hosting the backend in-process, so this file
//  now lives in the Ice target where all referenced types are local.
//  Adapted from singleton MenuBarItemManager.shared to instance
//  injection via configure() since Ice's manager is owned by AppState,
//  not a static singleton.
//

import Cocoa
import Foundation
import OSLog

// MARK: - Wire ↔ Ice Section Mapping

/// The wire enum uses `.alwaysVisible / .hidden / .alwaysHidden` (what
/// the MCP tool schema documents to LLM clients); Ice's internal
/// `MenuBarSection.Name` uses `.visible / .hidden / .alwaysHidden`.
/// Both sides round-trip through these converters so neither side has
/// to know about the other's spelling.
private extension MenuBarItemService.ItemSection {
    var iceSection: MenuBarSection.Name {
        switch self {
        case .alwaysVisible: return .visible
        case .hidden: return .hidden
        case .alwaysHidden: return .alwaysHidden
        }
    }
}

private extension MenuBarSection.Name {
    var wireSection: MenuBarItemService.ItemSection {
        switch self {
        case .visible: return .alwaysVisible
        case .hidden: return .hidden
        case .alwaysHidden: return .alwaysHidden
        }
    }
}

// MARK: - MCPBackendStateManager

/// In-process state manager for the MCP-extended XPC contract.
final class MCPBackendStateManager {
    /// The shared manager.
    static let shared = MCPBackendStateManager()

    /// UserDefaults key under which named MCP layouts are persisted.
    /// Format: `[layoutName: [sectionRawValue: [[bundleID: position]]]]`.
    ///
    /// Same key as `MenuBarItemService/MenuBarStateManager`'s read-only
    /// fire.6 implementation so save_layout writes from fire.6 are
    /// readable by apply_layout in fire.7.
    private static let layoutsKey = "MCPLayouts"

    /// The Ice main app's menu bar item manager. Set by
    /// `configure(itemManager:)` at app launch (from AppDelegate, once
    /// AppState has finished setup). Methods that need this return a
    /// clear "MCP backend not ready" error if called before configure().
    private var itemManager: MenuBarItemManager?

    private init() {}

    /// Wires the state manager to Ice's owned `MenuBarItemManager`
    /// instance. Must be called from AppDelegate after AppState's
    /// setup so `itemManager.itemCache` is populated by the time MCP
    /// clients start sending requests.
    func configure(itemManager: MenuBarItemManager) {
        self.itemManager = itemManager
    }

    // MARK: - Read

    /// Returns the list of menu bar items, optionally filtered to a
    /// single section.
    ///
    /// Uses Ice's existing `ItemCache` (the source of truth for
    /// section assignment), and resolves bundle IDs from the source PID.
    func listItems(
        section: MenuBarItemService.ItemSection?
    ) async -> [MenuBarItemService.ItemInfo] {
        Logger.default.debug(
            "MCPBackendStateManager.listItems(section: \(String(describing: section)))"
        )

        guard let manager = itemManager else {
            Logger.default.error("MCPBackendStateManager.listItems: itemManager not configured")
            return []
        }

        // Snapshot of every menu bar item across all displays. Empty
        // option set = no filter (returns everything the helper sees).
        let allItems = await MenuBarItem.getMenuBarItems(on: nil, option: [])

        // Use the existing cache from MenuBarItemManager to classify
        // items by section. The cache is computed by Ice's main loop
        // and is the source of truth for "which section is this item
        // in" - duplicating its position math would mean two
        // implementations to keep in sync.
        let cache = await MainActor.run { manager.itemCache }

        // Build a lookup: tag -> section, so we can classify in O(1).
        var sectionByTag = [MenuBarItemTag: MenuBarSection.Name]()
        for iceSection in MenuBarSection.Name.allCases {
            for item in cache.managedItems(for: iceSection) {
                sectionByTag[item.tag] = iceSection
            }
        }

        var results = [MenuBarItemService.ItemInfo]()
        var positionInSection = [MenuBarSection.Name: Int]()

        // The snapshot from getMenuBarItems is right-to-left visually
        // (it's reversed from CGS order). Walk it as-is; the order
        // within each section is what the position field reports.
        for item in allItems {
            guard let iceSection = sectionByTag[item.tag] else {
                // Control items, system clones, and items the cache
                // hasn't placed yet land here. Skip them - they're
                // not user-meaningful for MCP clients.
                continue
            }

            let wireSection = iceSection.wireSection
            if let filter = section, filter != wireSection {
                continue
            }

            let pid = item.sourcePID ?? item.ownerPID
            let bundleID = NSRunningApplication(processIdentifier: pid)?
                .bundleIdentifier ?? "unknown"

            let position = positionInSection[iceSection, default: 0]
            positionInSection[iceSection] = position + 1

            results.append(
                MenuBarItemService.ItemInfo(
                    bundleID: bundleID,
                    displayName: item.displayName,
                    windowID: UInt32(item.windowID),
                    section: wireSection,
                    position: position,
                    isOnScreen: item.isOnScreen
                )
            )
        }

        Logger.default.info(
            "MCPBackendStateManager.listItems returned \(results.count) items"
        )
        return results
    }

    // MARK: - Write (destructive)

    /// Moves an item identified by bundle ID to a target section,
    /// optionally at a specific index within that section.
    func moveItem(
        bundleID: String,
        toSection: MenuBarItemService.ItemSection,
        toIndex: Int?
    ) async -> (success: Bool, message: String?) {
        Logger.default.debug(
            "MCPBackendStateManager.moveItem(\(bundleID), to: \(toSection.rawValue), index: \(String(describing: toIndex)))"
        )

        guard let manager = itemManager else {
            return (false, "MCP backend not configured")
        }

        let iceSection = toSection.iceSection

        // Find the item we want to move.
        let snapshot = await MenuBarItem.getMenuBarItems(on: nil, option: [])
        let target = snapshot.first { item in
            let pid = item.sourcePID ?? item.ownerPID
            return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == bundleID
        }
        guard let target else {
            let message = "No menu bar item found with bundleID '\(bundleID)'"
            Logger.default.error("\(message)")
            return (false, message)
        }

        // Compute the destination. We work against the live cache
        // (post-snapshot) to avoid using stale positions.
        let cache = await MainActor.run { manager.itemCache }
        let sectionItems = cache.managedItems(for: iceSection)

        // Locate the section's control item - the hidden control item
        // for `.hidden`, the always-hidden control item for
        // `.alwaysHidden`, and the visible control item (i.e. the Ice
        // icon) for `.visible`. We need it as a fallback anchor when
        // the section is empty (nothing to position relative to).
        guard
            let controlItem = snapshot.first(where: { item in
                switch iceSection {
                case .visible: return item.tag == .visibleControlItem
                case .hidden: return item.tag == .hiddenControlItem
                case .alwaysHidden: return item.tag == .alwaysHiddenControlItem
                }
            })
        else {
            let message = "No control item found for section \(toSection.rawValue)"
            Logger.default.error("\(message)")
            return (false, message)
        }

        // Decide the destination.
        //
        // Section layout in CGS coordinates (right-to-left visually):
        //   [alwaysHidden items] [alwaysHiddenControl] [hidden items] [hiddenControl] [visible items] [visibleControl=Ice icon]
        //
        // `MoveDestination.rightOfItem(x)` means "to the right of x in
        // screen coordinates", which is the leftward end of the section
        // in our right-to-left visual sense - i.e. the FIRST position
        // within the section, just past the control item.
        let destination: MenuBarItemManager.MoveDestination

        if let toIndex, toIndex >= 0, toIndex < sectionItems.count {
            destination = .leftOfItem(sectionItems[toIndex])
        } else if let last = sectionItems.last {
            destination = .rightOfItem(last)
        } else {
            destination = .rightOfItem(controlItem)
        }

        // Perform the move. MenuBarItemManager is @MainActor and owns
        // the event semaphore; awaiting the move from this nonisolated
        // context hops automatically.
        do {
            try await manager.move(item: target, to: destination)
            Logger.default.info(
                "MCPBackendStateManager.moveItem(\(bundleID)) succeeded"
            )
            return (true, nil)
        } catch {
            let message = "Move failed: \(error)"
            Logger.default.error("MCPBackendStateManager.moveItem(\(bundleID)) \(message)")
            return (false, message)
        }
    }

    /// Convenience: move an item to the `.hidden` section.
    func hideItem(bundleID: String) async -> (success: Bool, message: String?) {
        await moveItem(bundleID: bundleID, toSection: .hidden, toIndex: nil)
    }

    /// Convenience: move an item to the `.alwaysVisible` section.
    func showItem(bundleID: String) async -> (success: Bool, message: String?) {
        await moveItem(bundleID: bundleID, toSection: .alwaysVisible, toIndex: nil)
    }

    /// Applies a previously saved layout (by name) from UserDefaults.
    func applyLayout(name: String) async -> (success: Bool, message: String?) {
        Logger.default.debug("MCPBackendStateManager.applyLayout(\(name))")

        guard
            let layouts = UserDefaults.standard.dictionary(forKey: Self.layoutsKey),
            let snapshot = layouts[name] as? [String: Any]
        else {
            let message = "Layout '\(name)' not found"
            Logger.default.error("\(message)")
            return (false, message)
        }

        // Walk sections in a deterministic order so applying the same
        // layout twice produces identical results.
        for wireSection in MenuBarItemService.ItemSection.allCases {
            let key = wireSection.rawValue
            guard let entries = snapshot[key] as? [[String: Int]] else {
                continue
            }

            // Replay in ascending position order - moving the item that
            // should land at position 0 first, then 1, and so on, so
            // each `moveItem` sees the section in the state implied by
            // the prior moves.
            let ordered = entries.sorted { lhs, rhs in
                (lhs.values.first ?? 0) < (rhs.values.first ?? 0)
            }

            for entry in ordered {
                guard let (bundleID, position) = entry.first else { continue }
                let result = await moveItem(
                    bundleID: bundleID,
                    toSection: wireSection,
                    toIndex: position
                )
                if !result.success {
                    let message = "Failed at \(bundleID): \(result.message ?? "unknown error")"
                    Logger.default.error("MCPBackendStateManager.applyLayout(\(name)) \(message)")
                    return (false, message)
                }
            }
        }

        Logger.default.info("MCPBackendStateManager.applyLayout(\(name)) succeeded")
        return (true, nil)
    }

    /// Saves the current menu bar state as a named layout in
    /// UserDefaults.
    ///
    /// - Returns: number of items captured on success, `nil` on failure.
    func saveLayout(name: String) async -> Int? {
        Logger.default.debug("MCPBackendStateManager.saveLayout(\(name))")

        guard let manager = itemManager else {
            Logger.default.error("MCPBackendStateManager.saveLayout: itemManager not configured")
            return nil
        }

        let cache = await MainActor.run { manager.itemCache }

        var snapshot = [String: [[String: Int]]]()
        var itemCount = 0

        for iceSection in MenuBarSection.Name.allCases {
            let items = cache.managedItems(for: iceSection)
            var entries = [[String: Int]]()
            for (position, item) in items.enumerated() {
                let pid = item.sourcePID ?? item.ownerPID
                guard let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else {
                    // Items without a resolvable bundle ID can't be
                    // replayed by applyLayout (which looks them up by
                    // bundle ID), so skip them here too.
                    continue
                }
                entries.append([bundleID: position])
                itemCount += 1
            }
            snapshot[iceSection.wireSection.rawValue] = entries
        }

        var existing = UserDefaults.standard.dictionary(forKey: Self.layoutsKey) ?? [:]
        existing[name] = snapshot
        UserDefaults.standard.set(existing, forKey: Self.layoutsKey)

        Logger.default.info(
            "MCPBackendStateManager.saveLayout(\(name)) saved \(itemCount) items"
        )
        return itemCount
    }
}
