//
//  AppDelegate.swift
//  Ice
//

import OSLog
import Sentry
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The shared app state.
    let appState = AppState()

    // MARK: NSApplicationDelegate Methods

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Initial chore work.
        NSSplitViewItem.swizzle()
        MigrationManager(appState: appState).migrateAll()

        // Initialize Sentry crash reporting BEFORE any other setup so we
        // capture even crashes that occur during early app launch.
        // Strict opt-in via Advanced Settings — defaults off, no data
        // leaves the device until the user explicitly enables it.
        startSentryIfOptedIn()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if #available(macOS 26.0, *) {
            FireMCPBridgeServer.shared.start()
        }

        // Hide the main menu's items to add additional space to the
        // menu bar when we are the focused app.
        for item in NSApp.mainMenu?.items ?? [] {
            item.isHidden = true
        }

        // Allow hiding the mouse while the app is in the background
        // to make menu bar item movement less jarring.
        Bridging.setConnectionProperty(true, forKey: "SetsCursorInBackground")

        #if DEBUG
        // Don't perform setup if running as a preview.
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return
        }
        #endif

        // Depending on the permissions state, either perform setup
        // or prompt to grant permissions.
        switch appState.permissions.permissionsState {
        case .hasAll:
            appState.permissions.logger.debug("Passed all permissions checks")
            appState.performSetup(hasPermissions: true)
        case .hasRequired:
            appState.permissions.logger.debug("Passed required permissions checks")
            appState.performSetup(hasPermissions: true)
        case .missing:
            appState.permissions.logger.debug("Failed required permissions checks")
            appState.performSetup(hasPermissions: false)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        Logger.default.debug("Handling reopen")
        openSettingsWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        if
            sender.isActive,
            sender.activationPolicy() != .accessory,
            appState.navigationState.isAppFrontmost
        {
            Logger.default.debug("All windows closed - deactivating with accessory activation policy")
            appState.deactivate(withPolicy: .accessory)
        }
        return false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        if #available(macOS 26.0, *) {
            FireMCPBridgeServer.shared.stop()
        }
    }

    // MARK: Other Methods

    /// Opens the settings window and activates the app.
    @objc func openSettingsWindow() {
        // Delay makes this more reliable for some reason.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [appState] in
            appState.activate(withPolicy: .regular)
            appState.openWindow(.settings)
        }
    }

    // MARK: Sentry

    /// Initializes the Sentry crash reporting SDK if the user has opted in
    /// via Advanced Settings → Privacy & Diagnostics.
    ///
    /// Privacy posture (Fire fork policy — stricter than Sentry's defaults):
    ///
    /// - **Opt-in only.** `Defaults.bool(forKey: .shareDiagnostics)` must be
    ///   `true` (the user explicitly flipped the toggle). Default is `false`.
    /// - **No PII.** `sendDefaultPii = false` strips IP, device names, user
    ///   identifiers.
    /// - **No screenshots, no view hierarchy.** Both disabled — menu bar
    ///   contents are user data we must not transmit.
    /// - **No session tracking, no user-interaction tracing, no auto-
    ///   performance tracing.** We collect crashes only, not behavioral data.
    ///
    /// What IS sent on crash: stack trace, thread state, macOS version, Ice
    /// version, CPU architecture. That is the minimum a maintainer needs to
    /// debug.
    private func startSentryIfOptedIn() {
        guard Defaults.bool(forKey: .shareDiagnostics) else {
            Logger.default.debug("Sentry: user has not opted in, skipping init")
            return
        }

        let marketingVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let buildVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.jordanbaird.Ice"

        SentrySDK.start { options in
            options.dsn = "https://3304125a913f6c0ade5859fd93c678e2@o4511453004169216.ingest.de.sentry.io/4511453022388304"
            options.releaseName = "\(bundleIdentifier)@\(marketingVersion)+\(buildVersion)"

            #if DEBUG
            options.environment = "debug"
            #else
            options.environment = "production"
            #endif

            // STRICT privacy — every default that could leak user data is off.
            // Note: attachScreenshot and attachViewHierarchy are iOS-only in
            // the Sentry Cocoa SDK (they require UIKit) — they don't exist on
            // macOS, so we don't need to disable them explicitly. The defaults
            // we DO disable here are the ones that exist on macOS.
            options.sendDefaultPii = false
            options.enableAutoSessionTracking = false
            options.enableAutoPerformanceTracing = false

            // Crashes only — disable network breadcrumbs (could leak menu bar
            // item update fetch URLs that include bundle IDs of running apps).
            options.enableNetworkBreadcrumbs = false

            // fire.10.4: best-effort filter for App Hang reports that are just
            // the main thread parked in a modal run loop — our own consent
            // prompts or Sparkle's "You're up to date" alert. FIRE-J and
            // FIRE-Q prove frame.function matching is not reliable at this
            // client-side stage. Final names may only be available after
            // server-side symbolication, but that explanation is unproven.
            // Only App Hang events are considered; genuine crashes that merely
            // happen during a modal are never dropped.
            options.beforeSend = { event in
                let isAppHang = (event.exceptions ?? []).contains { exception in
                    (exception.mechanism?.type.localizedCaseInsensitiveContains("apphang") ?? false)
                        || (exception.type?.localizedCaseInsensitiveContains("app hang") ?? false)
                }
                guard isAppHang else { return event }

                let modalMarkers = [
                    "runModal", "runModalSession", "beginSheetModal",
                    "SPUStandardUserDriver", "NSAlert", "_NSShowStopAlertPanel",
                    // An open NSMenu runs its own modal event loop, so a menu
                    // the user leaves open for >2 s reports as an App Hang.
                    // Sentry FIRE-Q was exactly this: our secondary context
                    // menu, held open while testing. The marker remains useful
                    // when the client already has a function name, but it did
                    // not suppress FIRE-Q reliably in 10.7/10.7.1.
                    "NSMenuTrackingSession", "NSContextMenuTrackingSession",
                    "startRunningMenuEventLoop",
                ]
                let parkedInModal = (event.threads ?? []).contains { thread in
                    (thread.stacktrace?.frames ?? []).contains { frame in
                        guard let function = frame.function else { return false }
                        return modalMarkers.contains { function.localizedCaseInsensitiveContains($0) }
                    }
                }
                return parkedInModal ? nil : event
            }

            // We do NOT use Sentry's automatic release-tracking based on
            // session counts — that requires session tracking which we disable.
        }

        Logger.default.info("Sentry: initialized for release \(marketingVersion)+\(buildVersion)")
    }
}
