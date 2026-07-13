//
//  SourcePIDCache.swift
//  MenuBarItemService
//

import AXSwift
import Cocoa
import Combine
import os

/// A cache for the source process identifiers for menu bar item windows.
///
/// We use the term "source process" to refer to the process that created
/// a menu bar item. Originally, we used the CGWindowList API to get the
/// window's owning process (`kCGWindowOwnerPID`), which was always the
/// source process. However, as of macOS 26, item windows are owned by
/// the Control Center.
///
/// We can find what we need using the Accessibility API, but doing it
/// efficiently ends up being a fairly complex process. Since calls to
/// Accessibility are thread blocking, we do most of the heavy lifting
/// in a dedicated XPC service, which we then call asynchronously from
/// the main app.
final class SourcePIDCache {
    /// An object that contains a running application and provides an
    /// interface to access relevant information, such as its process
    /// identifier and extras menu bar.
    private final class CachedApplication {
        private let runningApp: NSRunningApplication
        private let cachedProcessIdentifier: pid_t
        private let extrasMenuBar = OSAllocatedUnfairLock<UIElement?>(initialState: nil)

        /// The app's process identifier.
        var processIdentifier: pid_t {
            cachedProcessIdentifier
        }

        /// Whether this cached wrapper still represents a live process. PIDs
        /// can be reused after termination, so a dead wrapper must never be
        /// carried into a later refresh merely because the number matches.
        var canReuse: Bool {
            !runningApp.isTerminated
        }

        /// A Boolean value indicating whether the app's extras menu
        /// bar has been successfully created and stored.
        var hasExtrasMenuBar: Bool {
            extrasMenuBar.withLock { $0 != nil }
        }

        /// A Boolean value indicating whether the app is in a valid
        /// state for making accessibility calls.
        var isValidForAccessibility: Bool {
            // These checks help prevent blocking that can occur when
            // calling AX APIs while the app is an invalid state.
            runningApp.isFinishedLaunching &&
            !runningApp.isTerminated &&
            runningApp.activationPolicy != .prohibited &&
            !Bridging.isProcessUnresponsive(processIdentifier)
        }

        /// Creates a `CachedApplication` instance with the given running
        /// application.
        init(_ runningApp: NSRunningApplication) {
            self.runningApp = runningApp
            self.cachedProcessIdentifier = runningApp.processIdentifier
        }

        /// Returns the accessibility element representing the app's extras
        /// menu bar, creating it if necessary.
        ///
        /// When the element is first created, it gets stored for efficient
        /// access on subsequent calls.
        func getOrCreateExtrasMenuBar() -> UIElement? {
            if let cached = extrasMenuBar.withLock({ $0 }) {
                return cached
            }
            guard
                isValidForAccessibility,
                let app = AXHelpers.application(for: runningApp),
                let bar = AXHelpers.extrasMenuBar(for: app)
            else {
                return nil
            }
            return extrasMenuBar.withLock { cached in
                if let cached {
                    return cached
                }
                cached = bar
                return bar
            }
        }
    }

    /// State for the cache.
    private struct State {
        var apps = [CachedApplication]()
        var pids = [CGWindowID: pid_t]()

        /// Returns the latest bounds of the given window after ensuring
        /// that the bounds are stable (a.k.a. not currently changing).
        ///
        /// This method blocks until stable bounds can be determined, or
        /// until retrieving the bounds for the window fails.
        private func stableBounds(for window: WindowInfo) -> CGRect? {
            var cachedBounds = window.bounds

            for n in 1...5 {
                guard let currentBounds = window.currentBounds() else {
                    // Failure here means the window probably doesn't
                    // exist anymore.
                    return nil
                }
                if currentBounds == cachedBounds {
                    return currentBounds
                }
                cachedBounds = currentBounds
                // Compute the sleep interval from the current attempt.
                Thread.sleep(forTimeInterval: TimeInterval(n) / 100)
            }

            return nil
        }

        /// Reorders the cached apps so that those that are confirmed
        /// to have an extras menu bar are first in the array.
        private mutating func partitionApps() {
            var lhs = [CachedApplication]()
            var rhs = [CachedApplication]()

            for app in apps {
                if app.hasExtrasMenuBar {
                    lhs.append(app)
                } else {
                    rhs.append(app)
                }
            }

            apps = lhs + rhs
        }

        /// Updates the cached process identifier for the given window.
        mutating func updatePID(for window: WindowInfo) {
            guard
                AXHelpers.isProcessTrusted(),
                let windowBounds = stableBounds(for: window)
            else {
                return
            }

            partitionApps()

            for app in apps {
                guard let bar = app.getOrCreateExtrasMenuBar() else {
                    continue
                }
                for child in AXHelpers.children(for: bar) {
                    guard AXHelpers.isEnabled(child) else {
                        continue
                    }
                    guard
                        let childFrame = AXHelpers.frame(for: child),
                        childFrame.center.distance(to: windowBounds.center) <= 1
                    else {
                        continue
                    }
                    pids[window.windowID] = app.processIdentifier
                    return
                }
            }
        }
    }

    /// The shared cache.
    static let shared = SourcePIDCache()

    /// The cache's protected state.
    private let state = OSAllocatedUnfairLock(initialState: State())

    /// Refresh work never runs on the service's main run loop. The old KVO
    /// publisher for `runningApplications` rebuilt the entire cache on the main
    /// thread for every short-lived helper process — including Fire's own CLI
    /// bridge — which could starve the XPC listener.
    private let refreshQueue = DispatchQueue(
        label: "com.jordanbaird.Ice.SourcePIDCache.refresh",
        qos: .utility
    )

    /// Observe only meaningful app lifecycle notifications. Background helper
    /// processes use `.prohibited` activation policy and cannot own a menu bar
    /// extra, so they must not invalidate this cache.
    private lazy var cancellable: AnyCancellable = {
        let center = NSWorkspace.shared.notificationCenter
        return Publishers.Merge(
            center.publisher(for: NSWorkspace.didLaunchApplicationNotification),
            center.publisher(for: NSWorkspace.didTerminateApplicationNotification)
        )
        .receive(on: refreshQueue)
        .compactMap { notification in
            notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        }
        .filter { $0.activationPolicy != .prohibited }
        .debounce(for: .milliseconds(100), scheduler: refreshQueue)
        .sink { [weak self] _ in
            self?.refreshRunningApplications()
        }
    }()

    /// Creates the shared cache.
    private init() {
        Bridging.setProcessUnresponsiveTimeout(3)
    }

    /// Starts the observers for the cache.
    func start() {
        // AX timeouts are process-global, not app-global. Both XPC services run
        // in their own process, so relying on the main app's timeout left these
        // helpers exposed to the system's multi-second default.
        AXHelpers.limitGlobalMessagingTimeout()
        refreshRunningApplications()
        Logger.default.debug("Starting observers for source PID cache")
        _ = cancellable
    }

    /// Reconciles cached applications without holding the state lock across
    /// LaunchServices calls. Cached per-app AX elements survive the refresh.
    private func refreshRunningApplications() {
        let runningApps = NSWorkspace.shared.runningApplications
        let snapshot = state.withLock { ($0.apps, $0.pids) }
        let cachedApps = Dictionary(uniqueKeysWithValues: snapshot.0.map {
            ($0.processIdentifier, $0)
        })

        var refreshedApps = [CachedApplication]()
        refreshedApps.reserveCapacity(runningApps.count)
        var livePIDs = Set<pid_t>()
        for runningApp in runningApps {
            let pid = runningApp.processIdentifier
            livePIDs.insert(pid)
            if let cached = cachedApps[pid], cached.canReuse {
                refreshedApps.append(cached)
            } else {
                refreshedApps.append(CachedApplication(runningApp))
            }
        }

        let retainedPIDs = snapshot.1.filter { livePIDs.contains($0.value) }
        let appsToStore = refreshedApps
        state.withLock { state in
            state.apps = appsToStore
            state.pids = retainedPIDs
        }
        Logger.default.debug("Refreshed source PID applications")
    }

    /// Returns the cached process identifier for the given window,
    /// updating the cache if needed.
    func pid(for window: WindowInfo) -> pid_t? {
        state.withLock { state in
            if let pid = state.pids[window.windowID] {
                return pid
            }
            state.updatePID(for: window)
            return state.pids[window.windowID]
        }
    }
}
