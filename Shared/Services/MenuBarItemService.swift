//
//  MenuBarItemService.swift
//  Shared
//

import Foundation
import Security

enum MenuBarItemService {
    static let name = "com.jordanbaird.Ice.MenuBarItemService"

    /// Returns the Team Identifier of the currently running process, or
    /// `nil` if the binary is unsigned, ad-hoc signed, or the team
    /// identifier cannot be read.
    ///
    /// Both sides of the XPC connection (Ice ↔ MenuBarItemService.xpc) use
    /// this to decide whether to enforce `.isFromSameTeam()` on their
    /// peer requirements. The `.isFromSameTeam()` predicate silently
    /// rejects every peer when there's no team identifier to compare —
    /// the case for any ad-hoc-signed build, including every community
    /// fork shipped without an Apple Developer Program account. Without
    /// the guard, Ice rejects its own helper service, the helper
    /// rejects Ice back, and the Menu Bar Layout settings pane spins
    /// forever on "Loading menu bar items…". This is the same class as
    /// upstream issues #744 and #891.
    static func ownTeamIdentifier() -> String? {
        var staticCode: SecStaticCode?
        guard
            SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &staticCode) == errSecSuccess,
            let code = staticCode
        else {
            return nil
        }
        var info: CFDictionary?
        guard
            SecCodeCopySigningInformation(code, SecCSFlags(rawValue: 0), &info) == errSecSuccess,
            let dict = info as? [String: Any],
            let teamID = dict[kSecCodeInfoTeamIdentifier as String] as? String,
            !teamID.isEmpty
        else {
            return nil
        }
        return teamID
    }
}

extension MenuBarItemService {
    enum Request: Codable {
        case start
        case sourcePID(WindowInfo)

        // MARK: - MCP Server Extension (Phase 4.5)
        //
        // These cases exist so the future IceMCPBridge binary can speak
        // to the same XPC listener that the layout UI uses. Each maps
        // 1:1 to one of the six MVP tools defined in
        // docs/mcp/ARCHITECTURE.md §3.
        //
        // Phase 1 (this commit): wire contract only — handlers in
        // Listener.swift dispatch to MenuBarStateManager which returns
        // placeholder data. Phase 3 implements the real Accessibility-
        // backed read/write logic.

        /// Returns the list of menu bar items, optionally filtered to a
        /// single section. Maps to MCP `list_items` tool.
        case listItems(section: ItemSection?)

        /// Moves an item identified by bundle ID to a target section,
        /// optionally at a specific index within that section. Maps to
        /// MCP `move_item` tool.
        case moveItem(bundleID: String, toSection: ItemSection, toIndex: Int?)

        /// Convenience: moves an item to the `.hidden` section. Maps to
        /// MCP `hide_item` tool.
        case hideItem(bundleID: String)

        /// Convenience: moves an item to the `.alwaysVisible` section.
        /// Maps to MCP `show_item` tool.
        case showItem(bundleID: String)

        /// Applies a previously saved layout by name. Layouts are stored
        /// in the existing Ice plist (architecture decision Q2).
        /// Maps to MCP `apply_layout` tool.
        case applyLayout(name: String)

        /// Saves the current menu bar state as a named layout in the
        /// plist. Maps to MCP `save_layout` tool.
        case saveLayout(name: String)
    }

    enum Response: Codable {
        case start
        case sourcePID(pid_t?)

        // MARK: - MCP Server Extension (Phase 4.5)

        /// Response to `.listItems` — ordered list of items.
        case items([ItemInfo])

        /// Generic destructive-op response (move / hide / show / applyLayout).
        /// `undoToken` is `nil` in Phase 1 — Phase 5 wires the undo ring
        /// buffer.
        case mutationResult(success: Bool, undoToken: String?, message: String?)

        /// Response to `.saveLayout` — confirms the layout was persisted
        /// and reports how many items it captured.
        case layoutSaved(name: String, itemCount: Int)
    }

    // MARK: - Shared Model Types
    //
    // Sent over the XPC wire between Ice (client) and the XPC service
    // (server). Codable + Sendable. Both targets file-system-sync this
    // file via the Shared group so types stay in lockstep.

    /// Which visibility section an item belongs to.
    enum ItemSection: String, Codable, Sendable, CaseIterable {
        case alwaysVisible
        case hidden
        case alwaysHidden
    }

    /// Snapshot of a single menu bar item, returned by `.listItems`.
    struct ItemInfo: Codable, Sendable {
        /// Bundle identifier of the owning process (e.g. `com.apple.controlcenter`).
        let bundleID: String
        /// Human-readable name (typically the app name) — may be `nil`
        /// if the owning process exposes none.
        let displayName: String?
        /// CGWindowID of the item's status window.
        let windowID: UInt32
        /// Which section the item currently belongs to.
        let section: ItemSection
        /// 0-indexed position within the section (left to right).
        let position: Int
        /// Whether the item is currently on screen (versus hidden by
        /// Ice's auto-rehide or section state).
        let isOnScreen: Bool
    }
}
