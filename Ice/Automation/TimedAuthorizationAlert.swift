//
//  TimedAuthorizationAlert.swift
//  Ice
//

import AppKit
import os

/// Thread-safe marker used by Sentry's background `beforeSend` callback.
///
/// AppKit intentionally parks the main thread in a modal run loop while an
/// authorization alert is visible. Sentry otherwise reports that expected
/// wait as an App Hang. Marking only this narrow interval lets us suppress the
/// false positive without relying on client-side stack symbols (which may not
/// exist until the event reaches Sentry's symbolication service).
enum ExpectedAuthorizationModal {
    private static let activeCount = OSAllocatedUnfairLock(initialState: 0)

    static var isActive: Bool {
        activeCount.withLock { $0 > 0 }
    }

    static func begin() {
        activeCount.withLock { $0 += 1 }
    }

    static func end() {
        activeCount.withLock { $0 = max(0, $0 - 1) }
    }
}

/// Runs a blocking authorization prompt with a fail-closed deadline.
///
/// MCP clients have their own request deadlines. Without a shorter UI
/// deadline, a client can disappear while `NSAlert.runModal()` keeps the main
/// app's relay occupied indefinitely. Aborting the modal returns a response
/// that every caller treats as denial.
@MainActor
enum TimedAuthorizationAlert {
    static func run(_ alert: NSAlert, timeout: TimeInterval) -> NSApplication.ModalResponse {
        // Fire normally runs as an accessory app. `activate(ignoringOtherApps:)`
        // does not reliably bring an accessory-owned modal forward when no
        // Fire window is already open, leaving the request alive but invisible.
        // Promote only for the lifetime of the consent UI, then restore the
        // previous policy so Fire does not remain in the Dock or app switcher.
        let previousActivationPolicy = NSApp.activationPolicy()
        let previouslyVisibleWindows = Set(
            NSApp.windows.lazy.filter(\.isVisible).map(ObjectIdentifier.init)
        )
        if previousActivationPolicy != .regular {
            NSApp.setActivationPolicy(.regular)
            // Promoting an LSUIElement app can also reveal dormant SwiftUI
            // scenes. Keep every window that was hidden before consent hidden;
            // `runModal()` will present only the alert below.
            for window in NSApp.windows where !previouslyVisibleWindows.contains(ObjectIdentifier(window)) {
                window.orderOut(nil)
            }
        }
        if let frontmost = NSWorkspace.shared.frontmostApplication {
            NSRunningApplication.current.activate(from: frontmost)
        } else {
            NSRunningApplication.current.activate()
        }
        // The earlier activation request may have happened while Fire was
        // still an accessory app. Repeat it after promotion and explicitly
        // key the alert on the user's active Space.
        alert.window.collectionBehavior.insert(.moveToActiveSpace)
        NSApp.activate(ignoringOtherApps: true)
        alert.window.makeKeyAndOrderFront(nil)

        ExpectedAuthorizationModal.begin()
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
        defer {
            timer.invalidate()
            ExpectedAuthorizationModal.end()
            if previousActivationPolicy != .regular {
                NSApp.setActivationPolicy(previousActivationPolicy)
            }
        }
        return alert.runModal()
    }
}
