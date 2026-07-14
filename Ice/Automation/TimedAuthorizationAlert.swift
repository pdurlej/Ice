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
        let timer = Timer(timeInterval: timeout, repeats: false) { [weak alert] _ in
            guard let alert, NSApp.modalWindow === alert.window else {
                return
            }
            NSApp.abortModal()
        }
        // `runModal()` services AppKit's modal-panel run-loop mode, not the
        // main dispatch queue. Register directly in that mode so the deadline
        // still fires while the synchronous alert is waiting for input.
        RunLoop.main.add(timer, forMode: .modalPanel)
        defer { timer.invalidate() }
        return alert.runModal()
    }
}
