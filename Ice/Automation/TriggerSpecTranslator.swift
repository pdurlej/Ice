//
//  TriggerSpecTranslator.swift
//  Ice
//
//  Translates the agent-supplied, stringly-typed `MenuBarItemService.TriggerSpec`
//  (transport DTO) into Fire's validated domain `TriggerRule` (fire.10 P1).
//
//  This is a TRUST BOUNDARY: the spec crossed the XPC + file channel from an
//  agent, so every field is validated and clamped here. Anything malformed is
//  rejected with a clear, user-safe message — Fire never installs a half-parsed
//  automation, and the agent never controls authority, ids, or the seal. A new
//  rule always gets a freshly minted id and generation 1 (set_trigger creates;
//  it never edits an existing approved automation in place).
//

import Foundation

enum TriggerSpecTranslator {
    struct TranslationError: Error, CustomStringConvertible {
        let message: String
        var description: String { message }
    }

    /// Sane clamp range for an agent-suggested cooldown.
    private static let cooldownRange: ClosedRange<TimeInterval> = 1...3600

    static func makeRule(from spec: MenuBarItemService.TriggerSpec) throws -> TriggerRule {
        // The name is shown verbatim in the consent prompt, so it must be a
        // single safe display line — reject (not strip) control / newline /
        // bidi / zero-width trickery that could disguise what is being approved.
        guard let name = AgentInput.validName(spec.name) else {
            throw TranslationError(
                message: "name is required, must be at most 120 characters, and must not contain control, newline, or bidirectional/zero-width characters"
            )
        }

        let condition = try makeCondition(spec.condition)
        let action = try makeAction(spec.action)

        let cooldown: TimeInterval
        if let suggested = spec.cooldownSeconds {
            cooldown = min(max(suggested, cooldownRange.lowerBound), cooldownRange.upperBound)
        } else {
            cooldown = 5
        }

        return TriggerRule(
            name: name,
            enabled: false,            // authorizeInstall decides whether to enable
            generation: 1,
            condition: condition,
            onEnter: action,
            exitPolicy: .none,
            priority: 0,
            cooldown: cooldown
        )
    }

    // MARK: - Condition

    private static func makeCondition(
        _ spec: MenuBarItemService.TriggerSpec.ConditionSpec
    ) throws -> TriggerCondition {
        switch spec.type {
        case "appFocus":
            guard let bundleID = AgentInput.validBundleID(spec.bundleID ?? "") else {
                throw TranslationError(message: "appFocus requires a valid bundleID (reverse-DNS: letters, digits, dot, hyphen)")
            }
            let state: TriggerCondition.AppFocusState
            switch (spec.focusState ?? "active").lowercased() {
            case "active": state = .active
            case "inactive": state = .inactive
            default:
                throw TranslationError(message: "focusState must be \"active\" or \"inactive\"")
            }
            return .appFocus(bundleID: bundleID, state: state)

        case "batteryBelow":
            guard let percent = spec.percent else {
                throw TranslationError(message: "batteryBelow requires a percent")
            }
            guard (1...99).contains(percent) else {
                throw TranslationError(message: "percent must be between 1 and 99")
            }
            // Hysteresis is mandatory. Default 10 points above the trigger, clamped
            // to <= 100, and always strictly above `percent`.
            let resetAbove = spec.resetAbove ?? min(percent + 10, 100)
            guard resetAbove > percent, resetAbove <= 100 else {
                throw TranslationError(
                    message: "resetAbove (\(resetAbove)) must be greater than percent (\(percent)) and at most 100"
                )
            }
            return .batteryBelow(percent: percent, resetAbove: resetAbove)

        case "timeWindow":
            let rawDays = spec.days ?? []
            let days = Set(rawDays.compactMap { Weekday(rawValue: $0) })
            guard !days.isEmpty else {
                throw TranslationError(message: "timeWindow requires at least one valid day (1=Sun ... 7=Sat)")
            }
            let start = try makeTime(hour: spec.startHour, minute: spec.startMinute, label: "start")
            let end = try makeTime(hour: spec.endHour, minute: spec.endMinute, label: "end")
            guard start != end else {
                throw TranslationError(
                    message: "timeWindow start and end are identical — the window would never be active (for all day use 00:00–23:59)"
                )
            }
            let tzID = nonEmpty(spec.timeZoneID).flatMap { TimeZone(identifier: $0) != nil ? $0 : nil }
                ?? TimeZone.current.identifier
            return .timeWindow(days: days, start: start, end: end, timeZoneID: tzID)

        default:
            throw TranslationError(
                message: "unknown condition type \"\(spec.type)\"; expected appFocus, batteryBelow, or timeWindow"
            )
        }
    }

    private static func makeTime(hour: Int?, minute: Int?, label: String) throws -> LocalTime {
        let h = hour ?? 0
        let m = minute ?? 0
        guard (0...23).contains(h) else {
            throw TranslationError(message: "\(label)Hour must be between 0 and 23")
        }
        guard (0...59).contains(m) else {
            throw TranslationError(message: "\(label)Minute must be between 0 and 59")
        }
        return LocalTime(hour: h, minute: m)
    }

    // MARK: - Action

    private static func makeAction(
        _ spec: MenuBarItemService.TriggerSpec.ActionSpec
    ) throws -> TriggerAction {
        switch spec.type {
        case "setSection":
            let items = try makeItems(selectors: spec.selectors, bundleIDs: spec.bundleIDs, allowEmpty: false)
            guard let rawSection = spec.section, let section = TriggerSection(rawValue: rawSection) else {
                let valid = TriggerSection.allCases.map(\.rawValue).joined(separator: ", ")
                throw TranslationError(message: "section must be one of: \(valid)")
            }
            return .setSection(items: items, section: section)

        case "activateContext":
            let items = try makeItems(selectors: spec.selectors, bundleIDs: spec.bundleIDs, allowEmpty: true)
            let moves: [MovePlan]
            if items.isEmpty {
                moves = []
            } else {
                guard let rawSection = spec.section, let section = TriggerSection(rawValue: rawSection) else {
                    let valid = TriggerSection.allCases.map(\.rawValue).joined(separator: ", ")
                    throw TranslationError(message: "activateContext with menu bar items requires section: \(valid)")
                }
                moves = items.map { MovePlan(item: $0, toSection: section) }
            }

            let fireline: FirelinePayload
            switch spec.firelineType {
            case "hidden":
                fireline = .hidden
            case "quota":
                guard
                    let rawProvider = spec.firelineProvider,
                    let provider = FirelineQuotaProvider(rawValue: rawProvider)
                else {
                    let valid = FirelineQuotaProvider.allCases.map(\.rawValue).joined(separator: ", ")
                    throw TranslationError(message: "quota Fireline requires provider: \(valid)")
                }
                fireline = .quota(provider)
            case "menuBarItem":
                guard let selector = spec.firelineSelector else {
                    throw TranslationError(message: "menuBarItem Fireline requires fireline_selector from list_items")
                }
                fireline = .menuBarItem(try makeIdentity(selector))
            default:
                throw TranslationError(message: "activateContext requires fireline_type: hidden, quota, or menuBarItem")
            }

            guard !moves.isEmpty || fireline != .hidden else {
                throw TranslationError(message: "activateContext must move an item or show a Fireline payload")
            }
            return .activateContext(ContextSceneAction(moves: moves, fireline: fireline))

        default:
            throw TranslationError(
                message: "unknown action type \"\(spec.type)\"; expected setSection or activateContext"
            )
        }
    }

    private static func makeItems(
        selectors: [MenuBarItemService.ItemSelector]?,
        bundleIDs: [String]?,
        allowEmpty: Bool
    ) throws -> [ItemIdentity] {
        let suppliedSelectors = selectors ?? []
        let rawIDs = bundleIDs ?? []
        guard suppliedSelectors.isEmpty || rawIDs.isEmpty else {
            throw TranslationError(message: "provide selectors or bundleIDs, not both")
        }
        guard allowEmpty || !suppliedSelectors.isEmpty || !rawIDs.isEmpty else {
            throw TranslationError(message: "at least one selector or bundleID is required")
        }
        if !suppliedSelectors.isEmpty {
            return try suppliedSelectors.map(makeIdentity)
        }
        return try rawIDs.map { raw in
            guard let valid = AgentInput.validBundleID(raw) else {
                throw TranslationError(message: "every bundleID must be reverse-DNS (letters, digits, dot, hyphen)")
            }
            return ItemIdentity(bundleID: valid)
        }
    }

    private static func makeIdentity(
        _ selector: MenuBarItemService.ItemSelector
    ) throws -> ItemIdentity {
        guard selector.version == 1 else {
            throw TranslationError(message: "selector version must be 1")
        }
        guard
            let namespace = selector.namespace.flatMap({ AgentInput.validName($0, maxLength: 256) }),
            let title = selector.title.flatMap({ AgentInput.validName($0, maxLength: 256) }),
            let bundleID = AgentInput.validBundleID(selector.sourceBundleID)
        else {
            throw TranslationError(
                message: "every selector requires safe namespace, title, and source_bundle_id fields from list_items"
            )
        }
        return ItemIdentity(bundleID: bundleID, namespace: namespace, title: title)
    }

    // MARK: - Helpers

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

// MARK: - Summary view

extension MenuBarItemService.TriggerSummary {
    /// Builds the agent-facing read view of a rule using Fire-generated
    /// descriptions (never agent-supplied text).
    init(rule: TriggerRule) {
        self.init(
            id: rule.id.uuidString,
            name: rule.name,
            enabled: rule.enabled,
            conditionDescription: TriggerNarrator.describe(rule.condition),
            actionDescription: TriggerNarrator.describe(rule.onEnter)
        )
    }
}
