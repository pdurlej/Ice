//
//  AIQuotaBackend.swift
//  Ice
//
//  Abstraction over whatever produces quota snapshots. The MVP has one
//  implementation: CodexBarCLIQuotaBackend (shells out to the CodexBar
//  CLI). Kept as a protocol so a native vendored backend can replace it
//  later without touching the manager.
//

import Foundation

protocol AIQuotaBackend: Sendable {
    /// Fetches a snapshot for a single provider. Never throws: failures
    /// come back as an error-carrying snapshot so one bad provider can't
    /// abort a refresh of the others.
    func fetch(provider: AIQuotaProvider) async -> AIQuotaSnapshot

    /// Whether the backend is currently available (e.g. the CLI binary
    /// exists). Drives the "Install/Configure…" menu hint.
    var isAvailable: Bool { get }

    /// A human-readable hint describing why the backend is unavailable,
    /// or nil if it's available.
    var unavailableReason: String? { get }
}
