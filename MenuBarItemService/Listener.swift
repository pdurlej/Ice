//
//  Listener.swift
//  MenuBarItemService
//

import OSLog
import Security
import XPC

/// A wrapper around an XPC listener object.
final class Listener {
    /// The shared listener.
    static let shared = Listener()

    /// The service name.
    private let name = MenuBarItemService.name

    /// The underlying XPC listener object.
    private var listener: XPCListener?

    /// Creates the shared listener.
    private init() { }

    deinit {
        cancel()
    }

    /// Returns the Team Identifier of the currently running process, or
    /// `nil` if the binary is unsigned, ad-hoc signed, or the team
    /// identifier cannot be read.
    ///
    /// We need this because `.isFromSameTeam()` (used on macOS 26+ to
    /// constrain XPC peers) silently rejects every connection when the
    /// service binary has no team identifier — which is the case for any
    /// ad-hoc-signed build, including community forks that ship without
    /// an Apple Developer Program account. Without this check the XPC
    /// service rejects its own parent app with "Bogus check-in attempt",
    /// and the Menu Bar Layout pane spins forever on
    /// "Loading menu bar items…".
    private static func ownTeamIdentifier() -> String? {
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

    /// Handles a received message.
    private func handleMessage(_ message: XPCReceivedMessage) -> MenuBarItemService.Response? {
        do {
            let request = try message.decode(as: MenuBarItemService.Request.self)
            switch request {
            case .start:
                Logger.default.debug("Listener received start request")
                return .start
            case .sourcePID(let window):
                let pid = SourcePIDCache.shared.pid(for: window)
                return .sourcePID(pid)
            }
        } catch {
            Logger.default.error("Listener failed to handle message with error \(error)")
            return nil
        }
    }

    /// Activates the listener without checking if it is already active,
    /// with the requirement that session peers must be signed with the
    /// same team identifier as the service process.
    @available(macOS 26.0, *)
    private func uncheckedActivateWithSameTeamRequirement() throws {
        listener = try XPCListener(service: name, requirement: .isFromSameTeam()) { [weak self] request in
            request.accept { message in
                self?.handleMessage(message)
            }
        }
    }

    /// Activates the listener without checking if it is already active.
    private func uncheckedActivate() throws {
        listener = try XPCListener(service: name) { [weak self] request in
            request.accept { message in
                self?.handleMessage(message)
            }
        }
    }

    /// Activates the listener.
    func activate() {
        guard listener == nil else {
            Logger.default.notice("Listener is already active")
            return
        }

        Logger.default.debug("Activating listener")

        do {
            // On macOS 26+ the listener can constrain peers by team
            // identifier, but only when we actually have a team
            // identifier to compare against. Ad-hoc-signed builds (every
            // community fork without an Apple Developer Program account)
            // have no team identifier and would reject every connection
            // — including their own parent app — silently.
            if #available(macOS 26.0, *), Self.ownTeamIdentifier() != nil {
                try uncheckedActivateWithSameTeamRequirement()
            } else {
                try uncheckedActivate()
            }
        } catch {
            Logger.default.error("Failed to activate listener with error \(error)")
        }
    }

    /// Cancels the listener.
    func cancel() {
        Logger.default.debug("Canceling listener")
        listener.take()?.cancel()
    }
}
