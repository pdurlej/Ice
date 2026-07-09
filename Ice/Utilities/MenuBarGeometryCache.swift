//
//  MenuBarGeometryCache.swift
//  Ice
//
//  Off-main-refreshed cache of the menu bar geometry that the event-handler
//  guards consult (fire.10.7, issues #7 + #17).
//
//  Sentry FIRE-P: `isMouseInsideApplicationMenu` walked the frontmost app's
//  menu bar via the Accessibility API — synchronous IPC to that app — on the
//  main thread, on mouse events. When the frontmost app was busy, Fire's main
//  thread hung with it. Its sibling `isMouseInsideMenuBarItem` enumerated
//  every menu bar window (SkyLight calls) per event (issue #7).
//
//  Both guards now read this cache synchronously — zero IPC on the event
//  path and NO timing changes to the guard chain. The cache recomputes off
//  the main thread, event-driven (frontmost app, space, item cache, screen
//  changes, app launch/quit) plus a slow 2 s backstop tick, all debounced.
//  The bounded staleness is harmless here: items move when sections toggle
//  (covered by the item-cache trigger) and the app menu changes with the
//  frontmost app (covered); everything else drifts rarely.
//

import Cocoa
import Combine
import OSLog

@MainActor
final class MenuBarGeometryCache {
    private weak var appState: AppState?
    private var cancellables = Set<AnyCancellable>()

    /// Frame of the application menu per display, as computed by
    /// `NSScreen.getApplicationMenuFrame` (absent when unknown, or suppressed
    /// by its notch workaround).
    private(set) var applicationMenuFrames = [CGDirectDisplayID: CGRect]()

    /// Frames of ALL on-screen, active-space menu bar item windows —
    /// Apple's items included (unlike the item manager's ItemCache, which
    /// only tracks Ice-managed items; the guards must respect the clock and
    /// Control Center too).
    private(set) var menuBarItemFrames = [CGRect]()

    /// Serializes refreshes; a trigger landing mid-refresh queues exactly one
    /// follow-up so the cache always converges on fresh data.
    private var isRefreshing = false
    private var needsAnotherRefresh = false

    private let logger = Logger(category: "MenuBarGeometryCache")

    func performSetup(with appState: AppState) {
        self.appState = appState

        // Belt and suspenders for the whole process: cap how long ANY
        // Accessibility call may block on an unresponsive target app. The
        // refreshes below run off-main anyway; this bounds the residual
        // main-thread AX users (permission checks, hasValidMenuBar) well
        // below the 2 s hang threshold.
        AXHelpers.limitGlobalMessagingTimeout()

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let triggers: [AnyPublisher<Void, Never>] = [
            workspaceCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
                .map { _ in () }.eraseToAnyPublisher(),
            workspaceCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)
                .map { _ in () }.eraseToAnyPublisher(),
            workspaceCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)
                .map { _ in () }.eraseToAnyPublisher(),
            NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
                .map { _ in () }.eraseToAnyPublisher(),
            NSWorkspace.shared.publisher(for: \.frontmostApplication)
                .map { _ in () }.eraseToAnyPublisher(),
            NSWorkspace.shared.publisher(for: \.menuBarOwningApplication)
                .map { _ in () }.eraseToAnyPublisher(),
            appState.itemManager.$itemCache
                .map { _ in () }.eraseToAnyPublisher(),
            // Slow backstop for drift with no notification (an app renaming
            // its menus, an item resizing in place). The walk runs off-main
            // at utility QoS, so the cost is a few ms of background IPC.
            Timer.publish(every: 2, on: .main, in: .common).autoconnect()
                .map { _ in () }.eraseToAnyPublisher(),
        ]

        Publishers.MergeMany(triggers)
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] in
                self?.refresh()
            }
            .store(in: &cancellables)

        refresh()
        logger.debug("Menu bar geometry cache active")
    }

    /// The cached application-menu frame for a display.
    func applicationMenuFrame(for displayID: CGDirectDisplayID) -> CGRect? {
        applicationMenuFrames[displayID]
    }

    /// Whether a point (CoreGraphics coordinates) lies inside any cached
    /// menu bar item window.
    func isPointInsideMenuBarItem(_ point: CGPoint) -> Bool {
        menuBarItemFrames.contains { $0.contains(point) }
    }

    /// Recomputes the geometry off the main thread and publishes it back.
    private func refresh() {
        guard !isRefreshing else {
            needsAnotherRefresh = true
            return
        }
        isRefreshing = true

        // Snapshot the screens on the main actor; the AX + SkyLight walk runs
        // detached. Calling `getApplicationMenuFrame()` off-main is the same
        // (long-shipped) pattern MenuBarOverlayPanel's update task uses.
        let screens = NSScreen.screens
        Task.detached(priority: .utility) { [weak self] in
            var menuFrames = [CGDirectDisplayID: CGRect]()
            for screen in screens {
                if let frame = screen.getApplicationMenuFrame() {
                    menuFrames[screen.displayID] = frame
                }
            }

            let windowIDs = Bridging.getMenuBarWindowList(option: [.onScreen, .activeSpace, .itemsOnly])
            let itemFrames = windowIDs.compactMap { Bridging.getWindowBounds(for: $0) }

            await self?.publish(menuFrames: menuFrames, itemFrames: itemFrames)
        }
    }

    private func publish(menuFrames: [CGDirectDisplayID: CGRect], itemFrames: [CGRect]) {
        applicationMenuFrames = menuFrames
        menuBarItemFrames = itemFrames
        isRefreshing = false
        if needsAnotherRefresh {
            needsAnotherRefresh = false
            refresh()
        }
    }
}
