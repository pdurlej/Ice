//
//  MCPWriteChannel.swift
//  Shared
//
//  Wire model for agent-initiated menu-bar WRITE commands.
//
//  History: fire.8.2–fire.10.1 transported these over single-slot JSON files
//  in Application Support, because the Ice main app cannot host a launchd
//  Mach service (GUI apps are refused MachServices registration — the
//  documented "Option D" failure). fire.10.2 replaced the files with the XPC
//  relay: MCPBackend.xpc queues agent requests (`RelayQueue`) and the main
//  app pulls them over its own XPCSession (`MCPRelayPump`), peer-gated to
//  the same team on signed builds. That makes the channel AUTHENTICATED — a
//  same-user process can no longer inject commands or forge results — and
//  per-request replies remove the old single-slot overwrite race.
//
//  Only the model types remain here; the namespace keeps its historical
//  name. The consent prompt in the main app (`MCPWriteAuthorization`) stays
//  the user-facing authorization step; the authenticated relay is the
//  transport boundary underneath it.
//

import Foundation

enum MCPWriteChannel {
    /// A write command issued by MCPBackend on behalf of an agent, executed
    /// by the Ice main app.
    struct Command: Codable, Sendable {
        /// Unique per command, so the result can be correlated.
        let id: String
        /// Operation discriminator. Currently only "move".
        let op: String
        /// Bundle ID of the item to move (e.g. com.bitwarden.desktop).
        let bundleID: String
        /// Target section raw value: alwaysVisible | hidden | alwaysHidden.
        let toSection: String
        /// Optional intra-section index (currently advisory; Ice lands
        /// the item at the section edge).
        let toIndex: Int?
        /// Epoch seconds the command was created. The main app refuses
        /// commands older than `staleAfter` at fetch time.
        let createdAt: Double
    }

    /// The result of executing a `Command`, produced by the Ice main app.
    struct Result: Codable, Sendable {
        let id: String
        let success: Bool
        let message: String?
        let completedAt: Double
    }

    /// Commands older than this (seconds) are refused by the main app at
    /// fetch time — e.g. items that sat queued across a sleep/wake while the
    /// requesting bridge call long since timed out. Staleness is checked
    /// BEFORE the consent prompt, so a slow human approval still executes.
    static let staleAfter: TimeInterval = 10
}
