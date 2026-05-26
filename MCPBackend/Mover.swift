//
//  Mover.swift
//  MCPBackend
//
//  Lean menu bar item move logic for the MCPBackend.xpc service.
//
//  Carved out of Ice/MenuBar/MenuBarItems/MenuBarItemManager.swift's
//  move/postMoveEvents pipeline. Substantive differences from upstream:
//
//  - Decoupled from MenuBarItem struct (uses lean MoveItem snapshot)
//  - No AppState (no HIDEventManager coordination, no nav state)
//  - No AsyncSemaphore (single-flight via actor isolation)
//  - No move-operation-timeout cache (fixed timeouts)
//  - No cursor warp on return (CGWarpMouseCursorPosition behaves
//    inconsistently across macOS releases; cursor stays hidden through
//    the move so the user does not see it jump)
//
//  Cross-process subtlety: this runs in MCPBackend.xpc, not Ice main app.
//  Any HIDEventManager taps in Ice main app will still receive these
//  events system-wide. If feedback loops surface, the fix is for Ice to
//  teach its taps to drop events bearing our `eventSourceUserData`
//  sentinel (currently set to ObjectIdentifier of the local CGEvent,
//  same scheme upstream uses internally).
//

import Cocoa
import OSLog

/// Lean move logic for menu bar items, posted from an XPC service.
actor Mover {
    /// Shared instance.
    static let shared = Mover()

    private let logger = Logger(category: "Mover")

    /// Timestamp of the last successful move. Used to throttle back-to-back
    /// moves so the system has time to settle.
    private var lastMoveTimestamp: ContinuousClock.Instant?

    private init() {}

    // MARK: - Public Types

    /// A snapshot of the data needed to drag a single menu bar item.
    ///
    /// Caller (typically MCPBackendStateManager) builds this from a
    /// `MenuBarItem` it owns — Mover deliberately does not depend on
    /// the full MenuBarItem struct so it can live in the .xpc target
    /// without Ice's menu bar model code.
    struct MoveItem {
        /// CG window ID of the item's window. Used to look up current
        /// bounds at each step and to tag the synthetic mouse events.
        let windowID: CGWindowID

        /// PID of the process that owns the item's window (the
        /// receiver of system mouse events). On macOS 26 with Control
        /// Center reparenting, this is the Control Center for most
        /// items.
        let ownerPID: pid_t

        /// PID of the process that created the item, if known. For
        /// macOS 26 items lifted into Control Center, this is the
        /// originating app — events targeted at this PID are routed
        /// to the item more reliably than events targeted at the
        /// owner.
        let sourcePID: pid_t?

        /// Most-recent observed bounds. Mover re-queries Bridging
        /// before each event, but having a starting estimate lets us
        /// pick reasonable timeouts.
        let bounds: CGRect

        /// True for Control Center "Bento Box" group items, which
        /// typically take ~2x longer to respond to mouse events than
        /// regular items.
        let isBentoBox: Bool

        /// Display name used in error messages and logs. Not used
        /// for positioning logic.
        let displayName: String

        /// PID to use as the event target. Prefers sourcePID; falls
        /// back to ownerPID. Matches MenuBarItemManager.getEventPID.
        var eventPID: pid_t { sourcePID ?? ownerPID }
    }

    /// Where to drop a MoveItem.
    enum MoveDestination {
        case leftOfItem(MoveItem)
        case rightOfItem(MoveItem)

        var targetItem: MoveItem {
            switch self {
            case .leftOfItem(let item), .rightOfItem(let item): item
            }
        }

        var logString: String {
            switch self {
            case .leftOfItem(let item): "left of \(item.displayName) [\(item.windowID)]"
            case .rightOfItem(let item): "right of \(item.displayName) [\(item.windowID)]"
            }
        }
    }

    // MARK: - Errors

    enum MoveError: Error, CustomStringConvertible, LocalizedError {
        case cannotComplete
        case invalidEventSource
        case eventCreationFailure(itemName: String)
        case eventOperationTimeout(itemName: String)
        case itemResponseTimeout(itemName: String)
        case missingItemBounds(itemName: String)

        var description: String {
            switch self {
            case .cannotComplete:                       "Mover.cannotComplete"
            case .invalidEventSource:                   "Mover.invalidEventSource"
            case .eventCreationFailure(let n):          "Mover.eventCreationFailure(\(n))"
            case .eventOperationTimeout(let n):         "Mover.eventOperationTimeout(\(n))"
            case .itemResponseTimeout(let n):           "Mover.itemResponseTimeout(\(n))"
            case .missingItemBounds(let n):             "Mover.missingItemBounds(\(n))"
            }
        }

        var errorDescription: String? {
            switch self {
            case .cannotComplete:               "Move could not be completed"
            case .invalidEventSource:           "Invalid event source"
            case .eventCreationFailure(let n):  "Could not create event for \"\(n)\""
            case .eventOperationTimeout(let n): "Event operation timed out for \"\(n)\""
            case .itemResponseTimeout(let n):   "\"\(n)\" took too long to respond"
            case .missingItemBounds(let n):     "Missing bounds for \"\(n)\""
            }
        }
    }

    // MARK: - Public API

    /// Moves `item` to `destination` using synthetic ⌘-drag events.
    ///
    /// Retries up to 8 times. Each attempt re-queries current bounds
    /// (positions may shift after a previous move). Throws if no attempt
    /// succeeds.
    func move(item: MoveItem, to destination: MoveDestination) async throws {
        try await waitForMoveBuffer()

        logger.log("Moving \(item.displayName) [\(item.windowID)] to \(destination.logString)")

        guard try await !itemHasCorrectPosition(item: item, destination: destination) else {
            logger.debug("Already in position, no-op")
            return
        }

        MouseHelpers.hideCursor()
        defer { MouseHelpers.showCursor() }

        let maxAttempts = 8
        var lastError: Error?
        for attempt in 1...maxAttempts {
            try Task.checkCancellation()
            do {
                if try await itemHasCorrectPosition(item: item, destination: destination) {
                    logger.debug("Item arrived after attempt \(attempt - 1)")
                    return
                }
                try await postMoveEvents(item: item, destination: destination)
                logger.debug("Attempt \(attempt) succeeded")
                return
            } catch {
                lastError = error
                logger.debug("Attempt \(attempt) failed: \(error)")
                if attempt < maxAttempts {
                    try await waitForMoveBuffer()
                }
            }
        }
        throw lastError ?? MoveError.cannotComplete
    }

    // MARK: - Pipeline

    private func postMoveEvents(item: MoveItem, destination: MoveDestination) async throws {
        var itemOrigin = try await getCurrentBounds(for: item).origin
        let targetPoints = try await getTargetPoints(item: item, destination: destination)
        let source = try getEventSource()

        try permitLocalEvents()

        guard
            let mouseDown = CGEvent.menuBarItemMoveEvent(
                source: source, type: .mouseDown,
                location: targetPoints.start, windowID: item.windowID
            ),
            let mouseUp = CGEvent.menuBarItemMoveEvent(
                source: source, type: .mouseUp,
                location: targetPoints.end, windowID: destination.targetItem.windowID
            )
        else {
            throw MoveError.eventCreationFailure(itemName: item.displayName)
        }

        let timeout = item.isBentoBox ? Duration.milliseconds(120) : Duration.milliseconds(60)
        logger.debug("Move op timeout: \(timeout)")

        MouseHelpers.hideCursor()
        lastMoveTimestamp = .now
        defer {
            MouseHelpers.showCursor()
            lastMoveTimestamp = .now
        }

        do {
            try await scrombleEvent(mouseDown, item: item, timeout: timeout)
            itemOrigin = try await waitForResponse(
                item: item, initialOrigin: itemOrigin, timeout: timeout
            )
            try await scrombleEvent(mouseUp, item: item, timeout: timeout, repeating: 2)
            itemOrigin = try await waitForResponse(
                item: item, initialOrigin: itemOrigin, timeout: timeout
            )
        } catch {
            // Fallback: re-post mouseUp to make sure no item is stuck
            // in mid-drag from our half-completed attempt.
            do {
                try await scrombleEvent(
                    mouseUp, item: item, timeout: .milliseconds(100), repeating: 2
                )
            } catch {
                logger.error("Fallback mouseUp failed: \(error)")
            }
            throw error
        }
    }

    // MARK: - Geometry

    /// Returns the start/end mouse points needed to drag `item` to
    /// `destination`. Matches MenuBarItemManager.getTargetPoints math.
    private func getTargetPoints(
        item: MoveItem, destination: MoveDestination
    ) async throws -> (start: CGPoint, end: CGPoint) {
        let itemBounds = try await getCurrentBounds(for: item)
        let targetBounds = try await getCurrentBounds(for: destination.targetItem)
        switch destination {
        case .leftOfItem:
            var start = CGPoint(x: targetBounds.minX, y: targetBounds.minY)
            var end = start
            if itemBounds.maxX <= targetBounds.minX {
                end.x -= itemBounds.width            // moving right→left
            } else {
                start.x -= 1                          // moving left→right
            }
            return (start, end)
        case .rightOfItem:
            var start = CGPoint(x: targetBounds.maxX, y: targetBounds.minY)
            var end = start
            if itemBounds.minX <= targetBounds.maxX {
                end.x -= itemBounds.width            // moving right→left
            } else {
                start.x += 1                          // moving left→right
            }
            return (start, end)
        }
    }

    /// Reads the most recent screen-coordinate bounds for an item.
    private func getCurrentBounds(for item: MoveItem) async throws -> CGRect {
        let task = Task.detached(priority: .userInitiated) {
            guard let bounds = Bridging.getWindowBounds(for: item.windowID) else {
                throw MoveError.missingItemBounds(itemName: item.displayName)
            }
            return bounds
        }
        return try await task.value
    }

    private func itemHasCorrectPosition(
        item: MoveItem, destination: MoveDestination
    ) async throws -> Bool {
        let itemBounds = try await getCurrentBounds(for: item)
        let targetBounds = try await getCurrentBounds(for: destination.targetItem)
        return switch destination {
        case .leftOfItem:  itemBounds.maxX == targetBounds.minX
        case .rightOfItem: itemBounds.minX == targetBounds.maxX
        }
    }

    // MARK: - Event Plumbing

    private func getEventSource(
        with stateID: CGEventSourceStateID = .hidSystemState
    ) throws -> CGEventSource {
        // Per-actor cache — cheap re-use of the kernel object.
        if let cached = sourceCache[stateID] { return cached }
        guard let source = CGEventSource(stateID: stateID) else {
            throw MoveError.invalidEventSource
        }
        sourceCache[stateID] = source
        return source
    }
    private var sourceCache: [CGEventSourceStateID: CGEventSource] = [:]

    /// Disable event suppression so our synthetic events are honored
    /// even immediately after user mouse input.
    private func permitLocalEvents() throws {
        let source = try getEventSource(with: .combinedSessionState)
        let states: [CGEventSuppressionState] = [
            .eventSuppressionStateRemoteMouseDrag,
            .eventSuppressionStateSuppressionInterval,
        ]
        for state in states {
            source.setLocalEventsFilterDuringSuppressionState(
                .permitAllEvents, state: state
            )
        }
        source.localEventsSuppressionInterval = 0
    }

    private func waitForMoveBuffer() async throws {
        guard let last = lastMoveTimestamp else { return }
        let buffer = max(.milliseconds(25) - last.duration(to: .now), .zero)
        if buffer > .zero {
            do {
                try await Task.sleep(for: buffer)
            } catch {
                throw MoveError.cannotComplete
            }
        }
    }

    /// Waits for `item` to actually move from `initialOrigin`.
    /// Returns the new origin or throws on timeout.
    private nonisolated func waitForResponse(
        item: MoveItem, initialOrigin: CGPoint, timeout: Duration
    ) async throws -> CGPoint {
        let responseTask = Task.detached(priority: .userInitiated) {
            while true {
                try Task.checkCancellation()
                guard let bounds = Bridging.getWindowBounds(for: item.windowID) else {
                    throw MoveError.missingItemBounds(itemName: item.displayName)
                }
                if bounds.origin != initialOrigin {
                    return bounds.origin
                }
            }
        }
        let timeoutTask = Task(timeout: timeout) {
            try await withTaskCancellationHandler {
                try await responseTask.value
            } onCancel: {
                responseTask.cancel()
            }
        }
        do {
            return try await timeoutTask.value
        } catch is TaskTimeoutError {
            throw MoveError.itemResponseTimeout(itemName: item.displayName)
        } catch let error as MoveError {
            throw error
        } catch {
            throw MoveError.cannotComplete
        }
    }

    /// "Scrombles" an event through three EventTaps so we don't return
    /// until the system actually delivers the event to the target.
    /// Mirrors MenuBarItemManager.scrombleEvent — same three-tap dance,
    /// minus cursor warping.
    private nonisolated func scrombleEvent(
        _ event: CGEvent, item: MoveItem, timeout: Duration, repeating count: Int = 1
    ) async throws {
        MouseHelpers.hideCursor()
        defer { MouseHelpers.showCursor() }

        guard
            let entryEvent = CGEvent.uniqueNullEvent(),
            let exitEvent = CGEvent.uniqueNullEvent()
        else {
            throw MoveError.eventCreationFailure(itemName: item.displayName)
        }

        let pid = item.eventPID
        event.setTargetPID(pid)

        let firstLocation = EventTap.Location.pid(pid)
        let secondLocation = EventTap.Location.sessionEventTap

        var remaining = count
        var taps: [EventTap] = []

        let timeoutTask = Task(timeout: timeout * count) {
            try await withCheckedThrowingContinuation { continuation in
                // Tap 1: at first location (pid). Fires on entryEvent or exitEvent.
                let tap1 = EventTap(
                    label: "Mover.tap1",
                    type: .null,
                    location: firstLocation,
                    placement: .headInsertEventTap,
                    option: .defaultTap
                ) { tap, rEvent in
                    if rEvent.menuBarItemEventMatches(entryEvent) {
                        remaining -= 1
                        event.post(to: secondLocation)
                        return nil
                    }
                    if rEvent.menuBarItemEventMatches(exitEvent) {
                        tap.disable()
                        continuation.resume()
                        return nil
                    }
                    return rEvent
                }

                // Tap 2: at session event tap, listen-only. Fires when
                // our event reaches the session level, re-posts it to pid.
                let tap2 = EventTap(
                    label: "Mover.tap2",
                    type: event.type,
                    location: secondLocation,
                    placement: .tailAppendEventTap,
                    option: .listenOnly
                ) { tap, rEvent in
                    guard rEvent.matchesMenuBarItemEventFields(of: event) else {
                        return rEvent
                    }
                    if remaining <= 0 { tap.disable() }
                    event.post(to: firstLocation)
                    rEvent.setTargetPID(pid)
                    return rEvent
                }

                // Tap 3: at first location, listen-only. Fires when our
                // event arrives at pid; posts entry or exit to drive
                // Tap 1's continuation.
                let tap3 = EventTap(
                    label: "Mover.tap3",
                    type: event.type,
                    location: firstLocation,
                    placement: .headInsertEventTap,
                    option: .listenOnly
                ) { tap, rEvent in
                    guard rEvent.matchesMenuBarItemEventFields(of: event) else {
                        return rEvent
                    }
                    if remaining <= 0 {
                        tap.disable()
                        exitEvent.post(to: firstLocation)
                    } else {
                        entryEvent.post(to: firstLocation)
                    }
                    rEvent.setTargetPID(pid)
                    return rEvent
                }

                taps = [tap1, tap2, tap3]

                Task {
                    await withTaskCancellationHandler {
                        tap1.enable()
                        tap2.enable()
                        tap3.enable()
                        entryEvent.post(to: firstLocation)
                    } onCancel: {
                        tap1.disable()
                        tap2.disable()
                        tap3.disable()
                        continuation.resume(throwing: CancellationError())
                    }
                }
            }
        }

        do {
            try await timeoutTask.value
        } catch is TaskTimeoutError {
            throw MoveError.eventOperationTimeout(itemName: item.displayName)
        } catch {
            throw MoveError.cannotComplete
        }
    }
}

// MARK: - CGEvent helpers (lean adaptation of MenuBarItemManager's)

private extension CGEventField {
    /// CGEventField key for the window ID. Numeric per upstream Ice.
    static let _windowID = CGEventField(rawValue: 0x33)!
}

private extension CGEventFilterMask {
    static let permitAllEvents: CGEventFilterMask = [
        .permitLocalMouseEvents,
        .permitLocalKeyboardEvents,
        .permitSystemDefinedEvents,
    ]
}

private enum MoveEventType {
    case mouseDown
    case mouseUp

    var cgType: CGEventType {
        switch self {
        case .mouseDown: .leftMouseDown
        case .mouseUp:   .leftMouseUp
        }
    }
    var flags: CGEventFlags {
        // ⌘ down only on mouseDown; mouseUp clears.
        switch self {
        case .mouseDown: .maskCommand
        case .mouseUp:   []
        }
    }
}

fileprivate extension CGEvent {
    /// Creates a synthetic mouse event suitable for moving a menu bar
    /// item. Mirrors MenuBarItemManager's private menuBarItemEvent.
    static func menuBarItemMoveEvent(
        source: CGEventSource, type: MoveEventType,
        location: CGPoint, windowID: CGWindowID
    ) -> CGEvent? {
        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: type.cgType,
            mouseCursorPosition: location,
            mouseButton: .left
        ) else {
            return nil
        }
        event.flags = type.flags
        let uniqueBitPattern = Int64(Int(bitPattern: ObjectIdentifier(event)))
        event.setIntegerValueField(.eventSourceUserData, value: uniqueBitPattern)
        let wid = Int64(windowID)
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: wid)
        event.setIntegerValueField(
            .mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: wid
        )
        event.setIntegerValueField(CGEventField._windowID, value: wid)
        return event
    }

    /// Null event tagged with unique user data, used as a synchronization
    /// sentinel through the three-tap scrombler.
    static func uniqueNullEvent() -> CGEvent? {
        guard let event = CGEvent(source: nil) else { return nil }
        let uniqueBitPattern = Int64(Int(bitPattern: ObjectIdentifier(event)))
        event.setIntegerValueField(.eventSourceUserData, value: uniqueBitPattern)
        return event
    }

    func setTargetPID(_ pid: pid_t) {
        setIntegerValueField(.eventTargetUnixProcessID, value: Int64(pid))
    }

    func post(to location: EventTap.Location) {
        switch location {
        case .hidEventTap:               post(tap: .cghidEventTap)
        case .sessionEventTap:           post(tap: .cgSessionEventTap)
        case .annotatedSessionEventTap:  post(tap: .cgAnnotatedSessionEventTap)
        case .pid(let pid):              postToPid(pid)
        }
    }

    /// Compares this event's `eventSourceUserData` to another's.
    /// Two events from `uniqueNullEvent()` will never compare equal.
    func menuBarItemEventMatches(_ other: CGEvent) -> Bool {
        getIntegerValueField(.eventSourceUserData)
            == other.getIntegerValueField(.eventSourceUserData)
    }

    /// Compares this event's menu-bar-item fields to another's. Returns
    /// true iff all `eventSourceUserData`, both window-under-pointer
    /// fields, and the `windowID` numeric field match.
    func matchesMenuBarItemEventFields(of other: CGEvent) -> Bool {
        let fields: [CGEventField] = [
            .eventSourceUserData,
            .mouseEventWindowUnderMousePointer,
            .mouseEventWindowUnderMousePointerThatCanHandleThisEvent,
            CGEventField._windowID,
        ]
        return fields.allSatisfy { field in
            getIntegerValueField(field) == other.getIntegerValueField(field)
        }
    }
}
