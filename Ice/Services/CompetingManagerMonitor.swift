//
//  CompetingManagerMonitor.swift
//  Ice
//
//  Detects a competing menu bar manager and warns once instead of silently
//  fighting it (fire.10.6, issue #14).
//
//  Born from a real incident (2026-06-19): the owner enabled Bartender 6 next
//  to Fire and the menu bar "exploded" — both managers rearranging the same
//  NSStatusItems in a loop until logout. Nothing crashed, but a user who
//  doesn't know why their icons are dancing has no way to connect the chaos
//  to "two managers are installed". Beyond the visual fight, a second manager
//  also doubles window-server and Accessibility pressure — the amplifier
//  behind several of the App-Hang reports (FIRE-N/P).
//
//  Detection is a local bundle-identifier check against running apps; nothing
//  is recorded or transmitted (no Sentry breadcrumbs of the app list). Event-
//  driven only — one check at launch plus NSWorkspace launch notifications, no
//  polling. Each manager warns at most once per Fire session, and
//  `defaults write com.jordanbaird.Ice SuppressCompetingManagerWarning -bool true`
//  silences the feature entirely.
//

import Cocoa
import Combine
import OSLog

@MainActor
final class CompetingManagerMonitor {
    /// Known menu bar managers, by bundle identifier. Exact matches only, so
    /// an unknown app can never trigger a false positive; a missing entry is
    /// merely a false negative. Bartender's id is field-verified (seen live on
    /// the dogfooding machine); the rest come from the projects' public
    /// releases/sources.
    private static let knownManagers: [String: String] = [
        "com.surteesstudios.Bartender": "Bartender",
        "com.surteesstudios.Bartender-setapp": "Bartender",
        "dwarvesv.minimalbar": "Hidden Bar",
        "com.mortenjust.Dozer": "Dozer",
        "com.matthewpalmer.Vanilla": "Vanilla",
    ]

    private weak var appState: AppState?
    private var cancellable: AnyCancellable?

    /// Bundle ids already warned about this session — a manager the user
    /// keeps running shouldn't nag on every relaunch of it.
    private var warnedBundleIDs = Set<String>()

    private let logger = Logger(category: "CompetingManagerMonitor")

    func performSetup(with appState: AppState) {
        self.appState = appState

        guard !Defaults.bool(forKey: .suppressCompetingManagerWarning) else {
            logger.debug("Competing-manager warning suppressed by user default")
            return
        }

        // Anything already running when Fire starts…
        for app in NSWorkspace.shared.runningApplications {
            checkApplication(app)
        }

        // …and anything launched while Fire is running.
        cancellable = NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .compactMap { $0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication }
            .sink { [weak self] app in
                self?.checkApplication(app)
            }
    }

    private func checkApplication(_ app: NSRunningApplication) {
        guard
            let bundleID = app.bundleIdentifier,
            let name = Self.knownManagers[bundleID],
            !warnedBundleIDs.contains(bundleID)
        else {
            return
        }
        warnedBundleIDs.insert(bundleID)

        logger.notice("Competing menu bar manager detected: \(bundleID, privacy: .public)")

        guard let appState else { return }
        appState.userNotificationManager.requestAuthorization()
        appState.userNotificationManager.addRequest(
            with: .competingManager,
            title: "Another menu bar manager is running",
            body: """
                \(name) is also managing your menu bar. Two managers fight over \
                the same icons — consider quitting one of them.
                """
        )
    }
}
