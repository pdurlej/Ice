//
//  TimedAuthorizationAlert.swift
//  Ice
//

import AppKit

/// Runs a blocking authorization prompt with a fail-closed deadline.
///
/// MCP clients have their own request deadlines. Without a shorter UI
/// deadline, a client can disappear while `NSAlert.runModal()` keeps the main
/// app's relay occupied indefinitely. Aborting the modal returns a response
/// that every caller treats as denial.
@MainActor
enum TimedAuthorizationAlert {
    static func run(_ alert: NSAlert, timeout: TimeInterval) -> NSApplication.ModalResponse {
        let timeoutItem = DispatchWorkItem { [weak alert] in
            guard let alert, NSApp.modalWindow === alert.window else {
                return
            }
            NSApp.abortModal()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: timeoutItem)
        defer { timeoutItem.cancel() }
        return alert.runModal()
    }
}
