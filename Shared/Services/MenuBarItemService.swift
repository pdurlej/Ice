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

        /// Lists all saved layout names. Maps to MCP `list_layouts`
        /// tool. Added in fire.8 (W4 of the Fantastical-style "sets"
        /// rollout) so MCP clients can discover what layouts exist
        /// without trial-and-error apply_layout calls.
        case listLayouts

        // MARK: - AI-Native Triggers (fire.10 P1)
        //
        // The create/manage surface for automations. The agent supplies a
        // `TriggerSpec` ONLY — never authority and never the prompt text.
        // Fire's main app translates the spec into its domain `TriggerRule`,
        // GENERATES the consent prompt from its own canonical model, and binds
        // approval to the exact write set via a sealed (HMAC) grant. See
        // docs/mcp/AI-NATIVE-TRIGGERS.md §0.
        //
        // These cases are handled only by MCPBackend.xpc (which relays them to
        // the main app over the trigger file-channel). MenuBarItemService.xpc
        // rejects them.

        /// Proposes installing a new automation. The main app shows a consent
        /// prompt; approval mints a persistent, sealed capability. Maps to MCP
        /// `set_trigger`.
        case setTrigger(spec: TriggerSpec)

        /// Lists the user's installed automations (id, name, enabled, and
        /// Fire-generated human descriptions). Read-only. Maps to MCP
        /// `list_triggers`.
        case listTriggers

        /// Proposes removing an automation by id. The main app confirms before
        /// removing. Maps to MCP `remove_trigger`.
        case removeTrigger(id: String)

        // MARK: - Main-app relay (fire.10.2)
        //
        // The Ice main app PULLS agent-originated work from MCPBackend.xpc and
        // pushes results back over its own XPCSession — peer-gated to the same
        // team on signed builds. This replaced the fire.8.2 file channels: no
        // same-user process can inject or observe channel traffic anymore, and
        // per-request replies remove the single-slot overwrite race. Only
        // MCPBackend.xpc answers these; MenuBarItemService.xpc rejects them.

        /// Main app → MCPBackend: hand over the next queued agent request.
        case relayFetch

        /// Main app → MCPBackend: the result for a previously fetched request.
        case relayComplete(RelayResult)
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

        /// Response to `.listLayouts` — ordered list of layout names
        /// currently persisted in the plist. Empty array if no layouts
        /// have been saved yet.
        case layouts([String])

        // MARK: - AI-Native Triggers (fire.10 P1)

        /// Result of `.setTrigger` / `.removeTrigger`. `id` is the installed /
        /// removed trigger id (nil on failure or denial); `enabled` reflects
        /// whether an installed trigger is active. On denial `success` is
        /// `false` with a user-facing `message`.
        case triggerResult(success: Bool, id: String?, enabled: Bool, message: String?)

        /// Response to `.listTriggers` — the user's installed automations.
        case triggers([TriggerSummary])

        // MARK: - Main-app relay (fire.10.2)

        /// Reply to `.relayFetch` — the next queued agent request, if any.
        case relayWork(RelayWork?)

        /// Reply to `.relayComplete`.
        case relayAck
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

    // MARK: - Trigger transport DTOs (fire.10 P1)

    /// An agent-proposed automation in transport form. Deliberately flat and
    /// stringly-typed so it can cross the XPC + file-channel boundary without
    /// the rich domain enums (which live only in the Ice app target). The main
    /// app validates, clamps, and translates this into a domain `TriggerRule`;
    /// invalid specs are rejected with a clear message. The agent never
    /// supplies prompt text, authority, ids, or the seal — only this proposal.
    struct TriggerSpec: Codable, Sendable {
        /// Human-friendly automation name (shown in the consent prompt + UI).
        let name: String
        let condition: ConditionSpec
        let action: ActionSpec
        /// Client-suggested cooldown in seconds. Fire clamps to a sane range.
        let cooldownSeconds: Double?

        struct ConditionSpec: Codable, Sendable {
            /// One of: "appFocus", "batteryBelow", "timeWindow".
            let type: String

            // appFocus
            /// Bundle id whose focus state is watched.
            let bundleID: String?
            /// "active" (becomes frontmost) or "inactive" (stops being frontmost).
            let focusState: String?

            // batteryBelow
            /// Fire when battery drops below this percent (1...100).
            let percent: Int?
            /// Reset only above this percent (hysteresis; must exceed `percent`).
            let resetAbove: Int?

            // timeWindow
            /// Weekday numbers, 1 = Sunday ... 7 = Saturday.
            let days: [Int]?
            let startHour: Int?
            let startMinute: Int?
            let endHour: Int?
            let endMinute: Int?
            /// IANA tz id (e.g. "Europe/Warsaw"); defaults to the current zone.
            let timeZoneID: String?
        }

        struct ActionSpec: Codable, Sendable {
            /// P1 ships only "setSection" (applyLayoutSnapshot is UI-built so it
            /// can bind a content digest the agent has no way to compute).
            let type: String
            /// Bundle ids to move.
            let bundleIDs: [String]?
            /// Destination section raw value (alwaysVisible | hidden | alwaysHidden).
            let section: String?
        }
    }

    /// A read-only view of an installed automation, returned to the agent by
    /// `.listTriggers`. Carries no seal and no secrets — only what is safe to
    /// surface: id, name, enabled flag, and Fire-generated descriptions.
    struct TriggerSummary: Codable, Sendable {
        let id: String
        let name: String
        let enabled: Bool
        /// Fire-generated, e.g. "“com.tinyspeck.slackmacgap” becomes the frontmost app".
        let conditionDescription: String
        /// Fire-generated, e.g. "move “com.bitwarden.desktop” to the hidden section".
        let actionDescription: String
    }

    // MARK: - Relay payloads (fire.10.2)

    /// One queued, agent-originated request awaiting main-app fulfillment.
    enum RelayWork: Codable, Sendable {
        case move(MCPWriteChannel.Command)
        case trigger(MCPTriggerChannel.Proposal)

        /// Correlates the queued item with the bridge call awaiting it.
        var id: String {
            switch self {
            case .move(let command): command.id
            case .trigger(let proposal): proposal.id
            }
        }
    }

    /// The main app's result for a fetched `RelayWork`.
    enum RelayResult: Codable, Sendable {
        case move(MCPWriteChannel.Result)
        case trigger(MCPTriggerChannel.Result)

        /// Matches a result back to the bridge call awaiting it.
        var id: String {
            switch self {
            case .move(let result): result.id
            case .trigger(let result): result.id
            }
        }
    }
}
