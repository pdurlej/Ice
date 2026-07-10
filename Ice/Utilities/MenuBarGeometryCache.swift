//
//  MenuBarGeometryCache.swift
//  Ice
//
//  Off-main-refreshed cache of the APPLICATION MENU frame (fire.10.7.1,
//  issue #17 / Sentry FIRE-P).
//
//  FIRE-P: `isMouseInsideApplicationMenu` called
//  `NSScreen.getApplicationMenuFrame()` on the main thread, on every mouse
//  event. That walks the FRONTMOST APP's menu bar over the Accessibility API
//  — element / role / children / per-child isEnabled + frame, each a
//  synchronous IPC round trip into that app. When the frontmost app was busy,
//  Fire's main thread hung with it.
//
//  Caching is correct HERE because the value only changes when the frontmost
//  app (or its menus, or the screen layout) changes — never as a function of
//  mouse movement. The refresh is therefore triggered by exactly those events
//  and runs off the main thread; the guards read it synchronously.
//
//  WHAT THIS DELIBERATELY DOES NOT CACHE (fire.10.7 regression, reverted):
//  the menu bar ITEM frames used by `isMouseInsideMenuBarItem` (issue #7).
//  Those change at the very instant the guard is consulted — Ice expands and
//  collapses sections in response to the same events the guard gates — so any
//  cache is stale exactly when it matters. In testing that produced hover and
//  click actions that variously lagged, misfired, or did nothing at all.
//  `isMouseInsideMenuBarItem` keeps its live SkyLight query; it has never
//  produced an App-Hang report, unlike the AX walk above.
//

import Cocoa
import Combine
import OSLog

@MainActor
final class MenuBarGeometryCache {
    private weak var appState: AppState?
    private var cancellables = Set<AnyCancellable>()

    /// Frame of the application menu per display, as computed by
    /// `NSScreen.getApplicationMenuFrame()` off the main thread.
    private var applicationMenuFrames = [CGDirectDisplayID: CGRect]()

    /// Serializes refreshes; a trigger landing mid-refresh queues exactly one
    /// follow-up, so the cache always converges on fresh data without piling
    /// up AX walks.
    private var isRefreshing = false
    private var needsAnotherRefresh = false

    private let logger = Logger(category: "MenuBarGeometryCache")

    func performSetup(with appState: AppState) {
        self.appState = appState

        // Cap how long ANY Accessibility call from this process may block on
        // an unresponsive target app (system default is ~6 s). The walk below
        // runs off-main, so this mainly bounds the residual main-thread AX
        // users (permission checks, `hasValidMenuBar`) below the 2 s App-Hang
        // threshold.
        AXHelpers.limitGlobalMessagingTimeout()

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let triggers: [AnyPublisher<Void, Never>] = [
            // The app menu belongs to the frontmost / menu-bar-owning app —
            // these are the changes that actually invalidate the frame.
            NSWorkspace.shared.publisher(for: \.frontmostApplication)
                .map { _ in () }.eraseToAnyPublisher(),
            NSWorkspace.shared.publisher(for: \.menuBarOwningApplication)
                .map { _ in () }.eraseToAnyPublisher(),
            workspaceCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
                .map { _ in () }.eraseToAnyPublisher(),
            NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
                .map { _ in () }.eraseToAnyPublisher(),
            // Backstop for menus that change within one app (a document opens,
            // a mode switches) with no notification to hang off.
            Timer.publish(every: 2, on: .main, in: .common).autoconnect()
                .map { _ in () }.eraseToAnyPublisher(),
        ]

        // No debounce: an app switch must land before the user's next hover.
        // Bursts are coalesced by `isRefreshing`/`needsAnotherRefresh` instead.
        Publishers.MergeMany(triggers)
            .sink { [weak self] in
                self?.refresh()
            }
            .store(in: &cancellables)

        refresh()
        logger.debug("Menu bar geometry cache active")
    }

    /// The cached application-menu frame for a display, if known.
    func applicationMenuFrame(for displayID: CGDirectDisplayID) -> CGRect? {
        applicationMenuFrames[displayID]
    }

    /// Recomputes the application menu frames off the main thread.
    private func refresh() {
        guard !isRefreshing else {
            needsAnotherRefresh = true
            return
        }
        isRefreshing = true

        // Snapshot the screens on the main actor; the AX walk runs detached.
        // (MenuBarOverlayPanel's update task has called `getApplicationMenuFrame()`
        // off-main for many releases — this is the same, proven pattern.)
        let screens = NSScreen.screens.map { (id: $0.displayID, screen: $0) }
        let liveDisplayIDs = Set(screens.map(\.id))
        Task.detached(priority: .userInitiated) { [weak self] in
            var frames = [CGDirectDisplayID: CGRect]()
            for entry in screens {
                if let frame = entry.screen.getApplicationMenuFrame() {
                    frames[entry.id] = frame
                }
            }
            await self?.publish(frames, liveDisplayIDs: liveDisplayIDs)
        }
    }

    private func publish(_ frames: [CGDirectDisplayID: CGRect], liveDisplayIDs: Set<CGDirectDisplayID>) {
        // Drop only displays that are physically gone…
        applicationMenuFrames = applicationMenuFrames.filter { liveDisplayIDs.contains($0.key) }
        // …then MERGE, don't replace: a display whose walk produced nothing
        // this round (the AX messaging timeout fired, the app is mid-launch)
        // keeps its last good frame. Dropping it would make
        // `isMouseInsideApplicationMenu` answer "no" — i.e. treat the app menu
        // as empty menu bar space — and fire show-on-hover over File/Edit.
        for (displayID, frame) in frames {
            applicationMenuFrames[displayID] = frame
        }

        isRefreshing = false
        if needsAnotherRefresh {
            needsAnotherRefresh = false
            refresh()
        }
    }
}
