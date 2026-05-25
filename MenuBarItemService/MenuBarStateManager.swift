//
//  MenuBarStateManager.swift
//  MenuBarItemService
//
//  Manages read + write operations on the menu bar layout state on
//  behalf of the IceMCPBridge MCP server (Phase 4.5).
//
//  Phase 1 (this commit) — all operations are stubs that validate the
//  wire contract compiles and that requests round-trip correctly via
//  XPC. They return placeholder responses with `Not implemented in
//  Phase 1` messages so the MCP server scaffold (Phase 2) can be
//  built and exercised against a working contract.
//
//  Phase 3 will replace these stubs with real implementations backed
//  by:
//    - SourcePIDCache (already exists) for bundleID resolution
//    - AXHelpers (already exists) for Accessibility-driven section
//      assignment + position queries
//    - Ice's existing settings plist (com.jordanbaird.Ice.plist) for
//      layout persistence under a dedicated "MCPLayouts" key
//
//  Architecture decisions captured in docs/mcp/ARCHITECTURE.md §10.
//

import Foundation
import OSLog

/// Server-side state manager for the MCP-extended XPC contract.
///
/// Lives only in the `MenuBarItemService` XPC target — the main Ice
/// app never imports it. The wire types it speaks (`ItemInfo`,
/// `ItemSection`) come from `Shared/Services/MenuBarItemService.swift`.
final class MenuBarStateManager {
    /// The shared manager.
    static let shared = MenuBarStateManager()

    private init() {}

    // MARK: - Read

    /// Returns the list of menu bar items, optionally filtered to a
    /// single section.
    ///
    /// Phase 1: stub returning empty. Phase 3 wires this to
    /// SourcePIDCache + AXHelpers for a real snapshot.
    func listItems(section: MenuBarItemService.ItemSection?) -> [MenuBarItemService.ItemInfo] {
        Logger.default.debug(
            "MenuBarStateManager.listItems(section: \(String(describing: section)))"
        )
        return []
    }

    // MARK: - Write (destructive)

    /// Moves an item identified by bundle ID to a target section,
    /// optionally at a specific index within that section.
    ///
    /// - Returns: `(success, message)`. `success` is `false` and
    ///   `message` is non-nil in Phase 1 (always "not implemented").
    func moveItem(
        bundleID: String,
        toSection: MenuBarItemService.ItemSection,
        toIndex: Int?
    ) -> (success: Bool, message: String?) {
        Logger.default.debug(
            "MenuBarStateManager.moveItem(\(bundleID), to: \(toSection.rawValue), index: \(String(describing: toIndex)))"
        )
        return (false, "Not implemented in Phase 1 — wire-contract stub")
    }

    /// Convenience: move an item to the `.hidden` section.
    func hideItem(bundleID: String) -> (success: Bool, message: String?) {
        moveItem(bundleID: bundleID, toSection: .hidden, toIndex: nil)
    }

    /// Convenience: move an item to the `.alwaysVisible` section.
    func showItem(bundleID: String) -> (success: Bool, message: String?) {
        moveItem(bundleID: bundleID, toSection: .alwaysVisible, toIndex: nil)
    }

    /// Applies a previously saved layout (by name) from the plist.
    ///
    /// Phase 1: stub returning failure. Phase 3 reads `MCPLayouts/<name>`
    /// from `com.jordanbaird.Ice.plist` and applies item moves in batch.
    func applyLayout(name: String) -> (success: Bool, message: String?) {
        Logger.default.debug("MenuBarStateManager.applyLayout(\(name))")
        return (false, "Not implemented in Phase 1 — wire-contract stub")
    }

    /// Saves the current menu bar state as a named layout in the plist.
    ///
    /// - Returns: number of items captured on success, `nil` on failure.
    ///
    /// Phase 1: stub returning `nil`. Phase 3 snapshots current section
    /// assignments + positions and persists to `MCPLayouts/<name>` in
    /// the Ice plist.
    func saveLayout(name: String) -> Int? {
        Logger.default.debug("MenuBarStateManager.saveLayout(\(name))")
        return nil
    }
}
