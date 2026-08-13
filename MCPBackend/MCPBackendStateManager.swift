//
//  MCPBackendStateManager.swift
//  MCPBackend
//
//  Server-side state manager for the MCP backend XPC service.
//
//  W1 scope (this commit, paired with target scaffold):
//    - listItems(section:) - REAL, multi-display. Ported from
//      MenuBarItemService/MenuBarStateManager.swift's fire.7 impl with
//      the addition that this service uses ownerPID directly (no
//      SourcePIDCache available - that lives in MenuBarItemService.xpc
//      target). bundleID resolution may be less accurate on macOS 26
//      Control Center reparent cases; W2 decides whether to share
//      SourcePIDCache or accept ownerPID-only.
//    - saveLayout(name:) - REAL, writes to Ice's plist (suite name
//      com.jordanbaird.Ice so both old and new clients see the same
//      MCPLayouts dict).
//    - listLayouts() - REAL, reads from the same plist.
//    - moveItem / hideItem / showItem / applyLayout - STUB returning
//      "W2 placeholder" message. W2 ports the lean CGEvent posting
//      logic from Ice's MenuBarItemManager into a standalone helper
//      here. ~600-800 lines of careful porting.
//

import Cocoa
import Foundation
import OSLog

final class MCPBackendStateManager {
    /// The shared manager.
    static let shared = MCPBackendStateManager()

    /// UserDefaults key under which named MCP layouts are persisted.
    /// Same key as the legacy fire.6/fire.7 MenuBarStateManager so
    /// layouts saved in either service show up in the other.
    private static let layoutsKey = "MCPLayouts"

    /// Ice's main app bundle ID - used to identify Ice's control items
    /// in the menu bar (they sit at section boundaries) and as the
    /// UserDefaults suite for layout persistence.
    private static let iceBundleID = "com.jordanbaird.Ice"

    /// Ice's plist if accessible, else this service's own standard
    /// suite. Same fallback as MenuBarStateManager.
    private var defaults: UserDefaults {
        UserDefaults(suiteName: Self.iceBundleID) ?? .standard
    }

    private let logger = Logger(category: "MCPBackend.StateManager")

    private init() {}

    // MARK: - Read

    /// Returns the list of menu bar items across all active displays.
    /// fire.7-equivalent algorithm: iterate displays, find Ice control
    /// items per-display, bucket items by x-coord into sections.
    func listItems(section: MenuBarItemService.ItemSection?) async -> [MenuBarItemService.ItemInfo] {
        logger.debug("listItems(section: \(String(describing: section)))")

        let windowIDs = Bridging.getMenuBarWindowList(option: .itemsOnly)
        let allWindows = WindowInfo.createWindows(from: windowIDs)

        let displays = Self.activeDisplayIDs()

        var bucketed: [MenuBarItemService.ItemSection: [WindowInfo]] = [:]

        // Read Ice's three section-divider minX positions, published by
        // MenuBarManager.flushControlItemWindowIDs. Layout is
        // [visible.minX, hidden.minX, alwaysHidden.minX] in screen
        // coordinates. When a section is collapsed, Ice parks its
        // divider far off-screen (large negative X), which leaves the
        // section logically empty but its boundary still well-defined.
        //
        // Section membership rule:
        //   x > visible.minX        -> Apple-managed (Control Center, clock); skip
        //   hidden.minX < x <= visible.minX -> .alwaysVisible
        //   alwaysHidden.minX < x <= hidden.minX -> .hidden
        //   x <= alwaysHidden.minX -> .alwaysHidden
        // After a cfprefsd roundtrip, the [Double] we wrote can come back
        // as [NSNumber] (and "round" values may serialise as strings, so
        // also handle that). Coalesce defensively.
        let rawBoundaries = defaults.array(forKey: "IceControlItemMinX") ?? []
        let publishedBoundaries: [Double] = rawBoundaries.compactMap { value in
            if let n = value as? NSNumber { return n.doubleValue }
            if let d = value as? Double { return d }
            if let s = value as? String { return Double(s) }
            return nil
        }
        let visibleBoundary = publishedBoundaries.indices.contains(0) ? publishedBoundaries[0] : nil
        let hiddenBoundary = publishedBoundaries.indices.contains(1) ? publishedBoundaries[1] : nil
        let alwaysHiddenBoundary = publishedBoundaries.indices.contains(2) ? publishedBoundaries[2] : nil
        logger.debug("Boundaries published=\(publishedBoundaries.count) visible=\(String(describing: visibleBoundary)) hidden=\(String(describing: hiddenBoundary)) alwaysHidden=\(String(describing: alwaysHiddenBoundary))")

        for (displayIndex, displayID) in displays.enumerated() {
            let displayBounds = CGDisplayBounds(displayID)
            let displayWindows = allWindows.filter { window in
                displayBounds.contains(CGPoint(x: window.bounds.midX, y: window.bounds.midY))
            }

            guard let visibleBoundary,
                  let hiddenBoundary,
                  let alwaysHiddenBoundary
            else {
                logger.notice(
                    "Display \(displayIndex) (id=\(displayID)): Ice has not published control-item boundaries yet, bucketing everything as alwaysVisible"
                )
                bucketed[.alwaysVisible, default: []].append(
                    contentsOf: displayWindows.sorted { $0.bounds.minX < $1.bounds.minX }
                )
                continue
            }

            for window in displayWindows.sorted(by: { $0.bounds.minX < $1.bounds.minX }) {
                // Drop Apple's built-in Control Center widgets by
                // their stable window titles - they sit to the right
                // of Ice's visible boundary but are not Ice-managed.
                // Title check is cheap and bypasses the X-coordinate
                // ambiguity for items that landed in the gap between
                // Ice's visible divider and the first Apple widget.
                if let title = window.title,
                   title.hasPrefix("BentoBox") || title == "Clock" || title == "AudioVideoModule" || title == "FaceTime" || title == "MusicRecognition" {
                    continue
                }
                let x = window.bounds.minX
                let assigned: MenuBarItemService.ItemSection
                if x > hiddenBoundary {
                    assigned = .alwaysVisible
                } else if x > alwaysHiddenBoundary {
                    assigned = .hidden
                } else {
                    assigned = .alwaysHidden
                }
                bucketed[assigned, default: []].append(window)
            }
        }

        var results: [MenuBarItemService.ItemInfo] = []
        for assigned in MenuBarItemService.ItemSection.allCases {
            let windows = bucketed[assigned] ?? []
            for (position, window) in windows.enumerated() {
                results.append(makeItemInfo(window: window, section: assigned, position: position))
            }
        }

        if let section {
            return results.filter { $0.section == section }
        }
        return results
    }

    private func makeItemInfo(
        window: WindowInfo,
        section: MenuBarItemService.ItemSection,
        position: Int
    ) -> MenuBarItemService.ItemInfo {
        // Smoke test discovered the bundleIDs collapsed to
        // com.apple.controlcenter for every item on macOS 26 — that's
        // because ownerPID gets reparented to Control Center by the
        // system. Resolve the source PID via the AX cache (same
        // mechanism MenuBarItemService.xpc uses for the sourcePID
        // XPC handshake; promoted to Shared/ so both .xpc services
        // share the logic, though each process keeps its own cache).
        let sourcePID = SourcePIDCache.shared.pid(for: window)
        let resolvedPID = sourcePID ?? window.ownerPID
        let app = NSRunningApplication(processIdentifier: resolvedPID)
        let bundleID = app?.bundleIdentifier ?? window.ownerName ?? "unknown"
        let displayName = app?.localizedName ?? window.title ?? window.ownerName

        return MenuBarItemService.ItemInfo(
            bundleID: bundleID,
            displayName: displayName,
            windowID: window.windowID,
            section: section,
            position: position,
            isOnScreen: window.isOnScreen
        )
    }

    /// Returns the IDs of all active displays, with the main display
    /// first. In an XPC service `CGGetActiveDisplayList` sometimes
    /// returns zero displays because the process has no graphics
    /// connection until something forces one (it isn't a window-owning
    /// app). Fall back to `CGMainDisplayID()` in that case so list/move
    /// still works on the primary display.
    private static func activeDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            return [CGMainDisplayID()]
        }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else {
            return [CGMainDisplayID()]
        }
        let mainID = CGMainDisplayID()
        if let mainIndex = ids.firstIndex(of: mainID), mainIndex != 0 {
            ids.swapAt(0, mainIndex)
        }
        if ids.isEmpty {
            return [CGMainDisplayID()]
        }
        return ids
    }

    // MARK: - Write (delegated to Ice main app via the XPC relay)

    /// Moves the item with the given bundle ID to the target section by
    /// delegating to Ice main app through the relay queue (fire.10.2; the
    /// fire.8.2 file channel before that).
    ///
    /// Why delegate rather than move here: MCPBackend.xpc can only reach
    /// on-screen sections (its earlier in-process Mover worked for
    /// alwaysVisible↔alwaysVisible but could not move into a collapsed
    /// hidden / alwaysHidden section — those dividers are off-screen and
    /// expanding a section is an Ice-main-app-only operation). Ice main
    /// app owns the real control-item objects and `MenuBarItemManager.move`
    /// (the Layout-editor code path), so it handles every section.
    func moveItem(
        bundleID: String,
        toSection: MenuBarItemService.ItemSection,
        toIndex: Int?
    ) async -> (success: Bool, message: String?) {
        logger.debug(
            "moveItem(\(bundleID), to: \(toSection.rawValue), index: \(String(describing: toIndex))) via relay"
        )

        // Sanity: confirm the item is actually in the menu bar before
        // round-tripping to Ice, so we can return a fast, clear error.
        let windowIDs = Bridging.getMenuBarWindowList(option: .itemsOnly)
        let allWindows = WindowInfo.createWindows(from: windowIDs)
        guard findWindow(for: bundleID, in: allWindows) != nil else {
            return (false, "Item with bundle ID '\(bundleID)' not found in menu bar")
        }

        let command = MCPWriteChannel.Command(
            id: UUID().uuidString,
            op: "move",
            bundleID: bundleID,
            toSection: toSection.rawValue,
            toIndex: toIndex,
            createdAt: Date().timeIntervalSince1970
        )
        // 15s covers the main app's fetch latency (≤200ms), the consent
        // prompt fast path (active lease), and an AX move retry burst.
        guard case .move(let result)? = await RelayQueue.shared.submitAndWait(.move(command), timeout: 15) else {
            return (
                false,
                "Ice did not respond within 15s. Make sure Ice (Fire) is running and has Accessibility permission."
            )
        }
        logger.info("moveItem relay result for \(bundleID): success=\(result.success)")
        return (result.success, result.message)
    }

    func hideItem(bundleID: String) async -> (success: Bool, message: String?) {
        await moveItem(bundleID: bundleID, toSection: .hidden, toIndex: nil)
    }

    func showItem(bundleID: String) async -> (success: Bool, message: String?) {
        await moveItem(bundleID: bundleID, toSection: .alwaysVisible, toIndex: nil)
    }

    /// Applies a previously saved layout by replaying each item's
    /// recorded section assignment. Items not currently in the menu bar
    /// are skipped silently. First failure aborts and returns the
    /// partial state (rolling back would need the undo ring buffer,
    /// which lands in fire.8 W5 polish).
    func applyLayout(name: String) async -> (success: Bool, message: String?) {
        logger.debug("applyLayout(\(name))")

        guard
            let allLayouts = defaults.dictionary(forKey: Self.layoutsKey),
            let layout = allLayouts[name] as? [String: [[String: Any]]]
        else {
            return (false, "Layout '\(name)' not found")
        }

        // Replay order: alwaysHidden first (leftmost), then hidden, then
        // alwaysVisible. This minimises cascade re-positioning - if we
        // moved an alwaysVisible item first, then later moved an
        // alwaysHidden item, the alwaysVisible's index could shift.
        let replayOrder: [MenuBarItemService.ItemSection] = [
            .alwaysHidden, .hidden, .alwaysVisible,
        ]
        var moved = 0
        var skipped = 0
        for section in replayOrder {
            guard let entries = layout[section.rawValue] else { continue }
            // Within each section, preserve the position order.
            let sorted = entries.sorted { a, b in
                (a["position"] as? Int ?? 0) < (b["position"] as? Int ?? 0)
            }
            for entry in sorted {
                guard let bundleID = entry["bundleID"] as? String else { continue }
                let result = await moveItem(
                    bundleID: bundleID, toSection: section, toIndex: nil
                )
                if result.success {
                    moved += 1
                } else if let msg = result.message,
                          msg.contains("not found in menu bar") {
                    skipped += 1
                    logger.debug("applyLayout skipping absent item \(bundleID)")
                } else {
                    return (false, "Failed at \(bundleID) → \(section.rawValue): \(result.message ?? "unknown")")
                }
            }
        }
        return (true, "Applied layout '\(name)': moved \(moved) items, skipped \(skipped) absent")
    }

    // MARK: - W2 helpers

    /// Finds the menu bar window whose owning or source app has the
    /// given bundle ID. Skips Ice's own control items (which all share
    /// the Ice bundle ID and would confuse a "hide Ice" request).
    /// Checks both ownerPID (pre-macOS 26 / non-Control-Center items)
    /// and sourcePID via SourcePIDCache (macOS 26 Control Center
    /// reparented items).
    private func findWindow(
        for bundleID: String, in windows: [WindowInfo]
    ) -> WindowInfo? {
        guard bundleID != Self.iceBundleID else {
            return nil
        }
        return windows.first { window in
            // Try ownerPID first (cheap).
            if let owner = NSRunningApplication(processIdentifier: window.ownerPID),
               owner.bundleIdentifier == bundleID {
                return true
            }
            // Fall back to sourcePID (AX scan).
            if let sourcePID = SourcePIDCache.shared.pid(for: window),
               let source = NSRunningApplication(processIdentifier: sourcePID),
               source.bundleIdentifier == bundleID {
                return true
            }
            return false
        }
    }

    // MARK: - Save Layout / List Layouts (read-side write - implemented)

    func saveLayout(name: String) async -> Int? {
        logger.debug("saveLayout(\(name))")

        let items = await listItems(section: nil)
        guard !items.isEmpty else {
            logger.error("saveLayout: no items to snapshot - Ice may not be running")
            return nil
        }

        var snapshot: [String: [[String: Any]]] = [:]
        for item in items {
            var sectionEntries = snapshot[item.section.rawValue, default: []]
            sectionEntries.append([
                "bundleID": item.bundleID,
                "position": item.position,
                "displayName": item.displayName ?? "",
            ])
            snapshot[item.section.rawValue] = sectionEntries
        }

        var allLayouts: [String: Any] = defaults.dictionary(forKey: Self.layoutsKey) ?? [:]
        allLayouts[name] = snapshot
        defaults.set(allLayouts, forKey: Self.layoutsKey)

        logger.info("Saved layout '\(name)' with \(items.count) items")
        return items.count
    }

    /// Returns the names of all saved layouts, in stable alphabetical
    /// order. Reads from the same MCPLayouts dict that
    /// MenuBarItemService.MenuBarStateManager wrote to in fire.7.1.
    func listLayouts() -> [String] {
        logger.debug("listLayouts()")
        let layouts = defaults.dictionary(forKey: Self.layoutsKey) ?? [:]
        return layouts.keys.sorted()
    }

    // MARK: - AI-Native Triggers (fire.10 P1 - delegated to Ice main app)

    /// Bounds how many consent-class waits (`setTrigger` / `removeTrigger`) may
    /// be in flight at once (fire.10.6, issue #6). Each such request blocks an
    /// XPC worker thread in `syncWait` for up to 120 s while a human reads the
    /// consent prompt — and XPC dispatches from a bounded pool, so a burst of
    /// them could starve the pool until even `relayFetch` (which delivers the
    /// consent REPLIES) couldn't be served: deadlock-by-starvation. The relay
    /// pump processes one item at a time anyway, so a queued second proposal
    /// would just burn its whole timeout without its prompt even showing —
    /// failing fast is honest UX, not merely hygiene.
    private enum ConsentWaitGate {
        private static let lock = NSLock()
        private static var inFlight = 0
        static let limit = 2

        /// Reserves a slot; `false` means the caller must fail fast.
        static func tryEnter() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard inFlight < limit else { return false }
            inFlight += 1
            return true
        }

        static func leave() {
            lock.lock()
            defer { lock.unlock() }
            inFlight -= 1
        }
    }

    private static let consentBusyMessage =
        "Another automation approval is already pending in Fire. Wait for the user to decide it, then try again."

    /// Proposes installing a trigger. Relays the spec to Ice main app over the
    /// `MCPTriggerChannel`; the main app shows the install consent prompt, mints
    /// a sealed grant, and persists the rule. The agent never gets authority —
    /// only a yes/no plus the new id. The deadline is generous because a human
    /// must read and approve the prompt.
    func setTrigger(
        spec: MenuBarItemService.TriggerSpec
    ) async -> (success: Bool, triggerID: String?, enabled: Bool, message: String?) {
        logger.debug("setTrigger(name: \(spec.name)) via bridge")
        guard ConsentWaitGate.tryEnter() else {
            logger.notice("setTrigger rejected: consent-wait limit reached")
            return (false, nil, false, Self.consentBusyMessage)
        }
        defer { ConsentWaitGate.leave() }
        let proposal = MCPTriggerChannel.Proposal(
            id: UUID().uuidString,
            op: .install,
            spec: spec,
            triggerID: nil,
            createdAt: Date().timeIntervalSince1970
        )
        guard let result = await sendTriggerProposal(proposal, timeout: 120) else {
            return (false, nil, false,
                    "Ice did not respond. Make sure Fire is running, then approve the prompt within two minutes.")
        }
        return (result.success, result.triggerID, result.enabled, result.message)
    }

    /// Lists installed triggers by asking Ice main app (the authoritative
    /// `TriggerStore` owner). Read-only; short deadline.
    func listTriggers() async -> [MenuBarItemService.TriggerSummary] {
        logger.debug("listTriggers() via bridge")
        let proposal = MCPTriggerChannel.Proposal(
            id: UUID().uuidString,
            op: .list,
            spec: nil,
            triggerID: nil,
            createdAt: Date().timeIntervalSince1970
        )
        guard let result = await sendTriggerProposal(proposal, timeout: 10) else {
            return []
        }
        return result.triggers ?? []
    }

    /// Proposes removing a trigger by id. The main app confirms before deleting.
    func removeTrigger(
        id: String
    ) async -> (success: Bool, triggerID: String?, message: String?) {
        logger.debug("removeTrigger(\(id)) via bridge")
        guard ConsentWaitGate.tryEnter() else {
            logger.notice("removeTrigger rejected: consent-wait limit reached")
            return (false, nil, Self.consentBusyMessage)
        }
        defer { ConsentWaitGate.leave() }
        let proposal = MCPTriggerChannel.Proposal(
            id: UUID().uuidString,
            op: .remove,
            spec: nil,
            triggerID: id,
            createdAt: Date().timeIntervalSince1970
        )
        guard let result = await sendTriggerProposal(proposal, timeout: 60) else {
            return (false, nil,
                    "Ice did not respond. Make sure Fire is running, then confirm the removal prompt.")
        }
        return (result.success, result.triggerID, result.message)
    }

    /// Submits a proposal to the relay queue and suspends until the main app
    /// posts the result, up to `timeout` seconds. Returns nil on timeout.
    private func sendTriggerProposal(
        _ proposal: MCPTriggerChannel.Proposal,
        timeout: TimeInterval
    ) async -> MCPTriggerChannel.Result? {
        guard case .trigger(let result)? = await RelayQueue.shared.submitAndWait(.trigger(proposal), timeout: timeout) else {
            logger.notice("trigger proposal \(proposal.id) got no result within \(timeout)s")
            return nil
        }
        logger.info("trigger proposal \(proposal.id) result success=\(result.success)")
        return result
    }
}
