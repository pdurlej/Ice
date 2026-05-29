//
//  MCPWriteChannel.swift
//  Shared
//
//  A tiny file-based command/result channel between the MCPBackend.xpc
//  service and the Ice main app.
//
//  Why this exists
//  ---------------
//  MCPBackend.xpc can READ the menu bar layout fine (CGWindowList +
//  SourcePIDCache), and it can move items WITHIN an on-screen section
//  via Mover.swift. But it cannot move an item INTO a collapsed
//  section (hidden / alwaysHidden): those sections' divider control
//  items are parked off-screen and aren't enumerable from the XPC
//  service, and expanding a section is an Ice-main-app-only operation.
//
//  So write operations are delegated to Ice main app, which owns the
//  real control-item MenuBarItem objects and `MenuBarItemManager.move`
//  (the exact code path Ice's own Layout editor uses). MCPBackend
//  writes a Command file; Ice polls for it, executes the move, and
//  writes a Result file; MCPBackend polls for the matching result.
//
//  Why files and not the shared UserDefaults suite
//  -----------------------------------------------
//  Cross-process UserDefaults change propagation through cfprefsd is
//  unreliable for long-running readers (the value gets cached in the
//  reader process and there is no public "re-read from disk" API).
//  The minX publish works only because MCPBackend is a fresh process
//  per bridge connection. Here BOTH Ice (long-running) and
//  MCPBackend.xpc (lives across calls) are long-running, so we use
//  plain JSON files: `Data(contentsOf:)` always reads fresh bytes,
//  and `.atomic` writes give us tear-free swaps.
//
//  Both Ice.app and its .xpc services run unsandboxed (ENABLE_APP_SANDBOX
//  = NO), so they share the real `~/Library/Application Support`.
//

import Foundation

enum MCPWriteChannel {
    /// Shared directory under the user's Application Support. Created on
    /// first write. Same resolved path in Ice main app and the XPC
    /// service because both are unsandboxed.
    static let directory: URL = {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("com.jordanbaird.Ice", isDirectory: true)
            .appendingPathComponent("mcp", isDirectory: true)
    }()

    static let commandURL = directory.appendingPathComponent("write-command.json")
    static let resultURL = directory.appendingPathComponent("write-result.json")

    /// A write command issued by MCPBackend, executed by Ice main app.
    struct Command: Codable {
        /// Unique per command, so the result can be matched and stale
        /// results ignored.
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
        /// Epoch seconds the command was created. Ice ignores commands
        /// older than `staleAfter` so a crashed/quit MCPBackend doesn't
        /// leave a poison command on disk.
        let createdAt: Double
    }

    /// The result of executing a `Command`, written by Ice main app.
    struct Result: Codable {
        let id: String
        let success: Bool
        let message: String?
        let completedAt: Double
    }

    /// Commands older than this (seconds) are ignored by Ice. Kept tight
    /// so a stale/poison command can't be replayed long after it was
    /// written (the handler polls every 200ms, so legit pickup is
    /// effectively immediate). The consent prompt can take longer than
    /// this, but staleness is checked at pickup — before the prompt — so a
    /// slow human approval still executes.
    static let staleAfter: TimeInterval = 10

    private static func ensureDirectory() {
        let fm = FileManager.default
        try? fm.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        // Tighten an already-existing directory too (idempotent): owner-only,
        // so other users on the machine can't read or drop channel files.
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    /// Defense-in-depth: only trust a channel file that is a regular file
    /// (not a symlink), owned by THIS user, and of sane size. Blocks
    /// symlink tricks and cross-user writes. It does NOT stop a same-user
    /// attacker — the main app's `MCPWriteAuthorization` consent gate is
    /// the actual authorization boundary; this is hygiene.
    private static func isTrustedLocalFile(_ url: URL) -> Bool {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: url.path) else { return false }
        guard (attrs[.type] as? FileAttributeType) == .typeRegular else { return false }
        guard let owner = attrs[.ownerAccountID] as? NSNumber, owner.uint32Value == getuid() else { return false }
        guard let size = attrs[.size] as? NSNumber, size.intValue <= 16 * 1024 else { return false }
        return true
    }

    // MARK: Command (MCPBackend writes, Ice reads)

    static func writeCommand(_ command: Command) throws {
        ensureDirectory()
        let data = try JSONEncoder().encode(command)
        try data.write(to: commandURL, options: .atomic)
        // Owner-only regardless of umask.
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: commandURL.path
        )
    }

    static func readCommand() -> Command? {
        guard isTrustedLocalFile(commandURL) else { return nil }
        guard let data = try? Data(contentsOf: commandURL) else { return nil }
        return try? JSONDecoder().decode(Command.self, from: data)
    }

    // MARK: Result (Ice writes, MCPBackend reads)

    static func writeResult(_ result: Result) throws {
        ensureDirectory()
        let data = try JSONEncoder().encode(result)
        try data.write(to: resultURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: resultURL.path
        )
    }

    static func readResult() -> Result? {
        guard isTrustedLocalFile(resultURL) else { return nil }
        guard let data = try? Data(contentsOf: resultURL) else { return nil }
        return try? JSONDecoder().decode(Result.self, from: data)
    }
}
