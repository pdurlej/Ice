//
//  TriggerEngine.swift
//  Ice
//
//  Evaluates trigger conditions and fires approved automations (fire.10 P1).
//
//  P1 conditions: appFocus, batteryBelow (with hysteresis), timeWindow.
//  P1 semantics: EDGE-triggered on enter only (false → true), with a per-rule
//  cooldown. No continuous enforcement — a manual user move wins until the next
//  condition edge. Every fire re-validates the sealed grant, then enqueues a
//  MutationJob to the single MenuBarMutationCoordinator. The engine never
//  mutates the bar itself.
//

import AppKit
import Combine
import Foundation
import IOKit.ps
import OSLog

@MainActor
final class TriggerEngine {
    private weak var appState: AppState?
    private var cancellables = Set<AnyCancellable>()

    /// In-memory edge state (per-tick level), not persisted on every poll.
    private var levelState: [UUID: Bool] = [:]
    private var lastFired: [UUID: Date] = [:]

    private let logger = Logger(category: "TriggerEngine")

    func performSetup(with appState: AppState) {
        self.appState = appState
        TriggerStore.shared.load()

        // Seed edge + cooldown state from persistence WITHOUT firing — BEFORE
        // subscribing, so a notification arriving mid-setup can't fire against
        // an unseeded state. Only genuine condition edges after launch fire.
        seedState()

        // App-focus changes → re-evaluate immediately.
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didActivateApplicationNotification)
            .sink { [weak self] _ in self?.evaluateAll(reason: "appFocus") }
            .store(in: &cancellables)

        // Periodic re-evaluation for level conditions (battery, timeWindow).
        // 30s is plenty for a menu-bar automation and avoids busy-polling.
        Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.evaluateAll(reason: "timer") }
            .store(in: &cancellables)

        logger.debug("Trigger engine active (\(TriggerStore.shared.rules.count) rule(s))")
    }

    /// Seeds in-memory edge state (`levelState`) and cross-launch cooldown
    /// (`lastFired`) from persistence WITHOUT firing. Two fixes in one:
    /// - No re-fire on launch: an automation whose condition is already true at
    ///   login (e.g. "battery below 20%" while unplugged, or "Slack frontmost")
    ///   would otherwise see an empty levelState as a false→true edge and fire
    ///   on every launch, repeatedly overriding a manual arrangement.
    /// - Cooldown spans restarts: `lastFired` is seeded from the persisted
    ///   `lastFiredAt`, so the per-rule cooldown the user sees ("Last ran …")
    ///   is actually honored across relaunches instead of resetting each time.
    private func seedState() {
        for rule in TriggerStore.shared.rules where rule.enabled {
            levelState[rule.id] = currentLevel(rule)
            if let last = rule.lastFiredAt {
                lastFired[rule.id] = last
            }
        }
    }

    /// Re-reads rules after an install / remove / enable change.
    func reload() {
        TriggerStore.shared.load()
        if FirelineActivationState.shouldDeactivate(
            activeRuleID: appState?.firelineContextController.activeRuleID,
            rules: TriggerStore.shared.rules
        ) {
            appState?.firelineContextController.deactivate()
        }
        evaluateAll(reason: "reload")
    }

    // MARK: Evaluation

    private func evaluateAll(reason: String) {
        for rule in TriggerStore.shared.rules where rule.enabled {
            let now = currentLevel(rule)
            let previous = levelState[rule.id] ?? false
            levelState[rule.id] = now
            if now, !previous {  // false → true edge
                fire(rule, reason: reason)
            }
        }
    }

    private func fire(_ rule: TriggerRule, reason: String) {
        if let last = lastFired[rule.id], Date().timeIntervalSince(last) < rule.cooldown {
            return
        }

        // Re-validate the sealed grant immediately before acting — guards a
        // defaults-edited rule whose seal no longer matches its content.
        let sealed = TriggerStore.shared.sealedGrant(for: rule.id)
        guard AutomationAuthorization.shared.validateForFire(rule: rule, sealed: sealed) else {
            logger.warning("Trigger \(rule.id, privacy: .public) fire blocked: invalid/missing grant")
            return
        }
        lastFired[rule.id] = Date()
        TriggerStore.shared.recordFired(id: rule.id)  // audit trail for the UI

        let job = MutationJob(
            source: .trigger,
            triggerID: rule.id,
            triggerGeneration: rule.generation,
            moves: rule.onEnter.writeSet
        )
        logger.log("Trigger fired (\(reason, privacy: .public)): \(rule.id, privacy: .public) — \(job.moves.count) move(s)")
        Task {
            let result = await MenuBarMutationCoordinator.shared.enqueue(job)
            logger.log("Trigger \(rule.id, privacy: .public) result success=\(result.success) moved=\(result.movedCount)")
            if result.success {
                appState?.firelineContextController.activate(rule: rule)
            }
        }
    }

    // MARK: Condition level (battery hysteresis lives here)

    private func currentLevel(_ rule: TriggerRule) -> Bool {
        switch rule.condition {
        case .appFocus(let bundleID, let state):
            let isFront = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID
            return state == .active ? isFront : !isFront

        case .batteryBelow(let percent, let resetAbove):
            guard let battery = Self.batteryPercent() else { return false }
            // Once below, stay true until above resetAbove (no flapping).
            if levelState[rule.id] == true {
                return battery < resetAbove
            }
            return battery < percent

        case .timeWindow(let days, let start, let end, let timeZoneID):
            return TimeWindow.contains(days: days, start: start, end: end, timeZoneID: timeZoneID, now: Date())
        }
    }

    // MARK: Sources

    private static func batteryPercent() -> Int? {
        guard
            let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return nil
        }
        for source in sources {
            guard
                let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any]
            else {
                continue
            }
            if
                let current = description[kIOPSCurrentCapacityKey as String] as? Int,
                let maximum = description[kIOPSMaxCapacityKey as String] as? Int,
                maximum > 0
            {
                return Int((Double(current) / Double(maximum)) * 100.0)
            }
        }
        return nil
    }
}
