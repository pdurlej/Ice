//
//  TriggerStore.swift
//  Ice
//
//  Persistence for AI-Native Triggers (fire.10 P1).
//
//  Trigger rules are CONFIG (UserDefaults, like MCPLayouts). Their AUTHORITY is
//  a separate sealed grant (AutomationGrantStore). On load, any enabled rule
//  whose sealed grant is missing, stale (wrong generation), or tampered is
//  force-disabled with `.approvalMissingOrTampered` — defaults alone never
//  authorize an automation.
//

import Foundation
import OSLog

@MainActor
final class TriggerStore: ObservableObject {
    static let shared = TriggerStore()

    private let rulesKey = "Triggers"
    private let grantsKey = "TriggerGrants"
    private let fire1RulesKey = "ContextScenesV1"
    private let fire1GrantsKey = "ContextSceneGrantsV1"
    private let logger = Logger(category: "TriggerStore")

    private init() {}

    /// The current rules. Mutated only through this store so persistence and
    /// grant validation stay in lockstep. `@Published` so the Automations
    /// settings pane reflects installs / removals / fires live.
    @Published private(set) var rules: [TriggerRule] = []

    /// Loads rules from defaults and validates each enabled rule's sealed
    /// grant, disabling any that fail.
    func load() {
        let storedRules = mergedByID(
            (decode([TriggerRule].self, key: rulesKey) ?? [])
                + (decode([TriggerRule].self, key: fire1RulesKey) ?? [])
        )
        let sealedGrants = allSealedGrants()
        let grantByTrigger = Dictionary(
            sealedGrants.map { ($0.grant.triggerID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        rules = storedRules.map { rule in
            guard rule.enabled else { return rule }
            guard
                let sealed = grantByTrigger[rule.id],
                sealed.grant.generation == rule.generation,
                sealed.grant.canonicalDigest == TriggerCanonicalizer.digest(condition: rule.condition, action: rule.onEnter),
                AutomationGrantStore.shared.validates(sealed)
            else {
                // Bind "enabled" to the grant's CONTENT digest, not just its MAC:
                // a rule whose condition/action/write-set drifted from what was
                // approved is force-disabled here so the UI honestly shows
                // "Re-approve…" instead of appearing enabled but silently never
                // firing (validateForFire would block it). This is also the
                // clean migration for the fire.10.3 canonical-form change:
                // pre-10.3 grants carry an old-formula digest, so existing
                // automations land here once and need a one-click re-approval
                // (no unsafe auto-re-seal — we can't prove an unchanged
                // condition from the old non-deterministic digest).
                logger.warning("Trigger \(rule.id, privacy: .public) disabled: grant missing/stale/digest-mismatch/tampered")
                var disabled = rule
                disabled.enabled = false
                return disabled
            }
            return rule
        }
        // Always rewrite the partition. This also migrates any Fire 1.0 beta
        // payload that was briefly written into the legacy atomic array.
        persistRules()
        persistGrantPartitions(sealedGrants, rules: rules)
        logger.debug("Loaded \(self.rules.count) trigger(s)")
    }

    /// Inserts or replaces a rule and (optionally) its sealed grant.
    func upsert(_ rule: TriggerRule, grant: SealedGrant?) {
        rules.removeAll { $0.id == rule.id }
        rules.append(rule)
        persistRules()
        if let grant {
            persistGrant(grant, for: rule)
        }
    }

    func remove(id: UUID) {
        rules.removeAll { $0.id == id }
        persistRules()
        removeGrant(triggerID: id)
    }

    /// Enables/disables a rule. Enabling requires a still-valid grant; callers
    /// should re-run authorization if the grant is missing.
    @discardableResult
    func setEnabled(_ enabled: Bool, id: UUID) -> Bool {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return false }
        if enabled {
            guard
                let sealed = sealedGrant(for: id),
                sealed.grant.generation == rules[index].generation,
                AutomationGrantStore.shared.validates(sealed)
            else {
                logger.warning("Refusing to enable \(id, privacy: .public): no valid grant")
                return false
            }
        }
        rules[index].enabled = enabled
        persistRules()
        return true
    }

    /// The sealed grant for a trigger, if any. The engine re-validates this
    /// immediately before each auto-fire.
    func sealedGrant(for id: UUID) -> SealedGrant? {
        allSealedGrants().first { $0.grant.triggerID == id }
    }

    /// Whether `rule` currently has a sealed grant that matches its content and
    /// generation. The Automations UI uses this to show whether a disabled rule
    /// can be turned on, or needs re-approval.
    func hasValidGrant(for rule: TriggerRule) -> Bool {
        guard
            let sealed = sealedGrant(for: rule.id),
            sealed.grant.generation == rule.generation,
            AutomationGrantStore.shared.validates(sealed)
        else {
            return false
        }
        return true
    }

    /// Records a successful auto-fire's timestamp (audit trail in the UI). Only
    /// touches `lastFiredAt`, so it never changes the canonical digest and the
    /// sealed grant stays valid.
    func recordFired(id: UUID, at date: Date = Date()) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
        rules[index].lastFiredAt = date
        persistRules()
    }

    /// Global kill switch: disables every enabled rule. Returns the number
    /// disabled. The engine should `reload()` afterward.
    @discardableResult
    func disableAll() -> Int {
        var count = 0
        for index in rules.indices where rules[index].enabled {
            rules[index].enabled = false
            count += 1
        }
        if count > 0 {
            persistRules()
            logger.log("Disabled all (\(count, privacy: .public)) trigger(s)")
        }
        return count
    }

    // MARK: Persistence

    private func persistRules() {
        let encoder = JSONEncoder()
        let legacy = rules.filter { $0.onEnter.isLegacyStorageCompatible }
        let fire1 = rules.filter { !$0.onEnter.isLegacyStorageCompatible }
        if let data = try? encoder.encode(legacy) {
            UserDefaults.standard.set(data, forKey: rulesKey)
        }
        if let data = try? encoder.encode(fire1) {
            UserDefaults.standard.set(data, forKey: fire1RulesKey)
        }
    }

    private func persistGrant(_ sealed: SealedGrant, for rule: TriggerRule) {
        removeGrant(triggerID: sealed.grant.triggerID)
        let key = rule.onEnter.isLegacyStorageCompatible ? grantsKey : fire1GrantsKey
        var grants = decode([SealedGrant].self, key: key) ?? []
        grants.append(sealed)
        persist(grants, key: key)
    }

    private func removeGrant(triggerID: UUID) {
        for key in [grantsKey, fire1GrantsKey] {
            var grants = decode([SealedGrant].self, key: key) ?? []
            grants.removeAll { $0.grant.triggerID == triggerID }
            persist(grants, key: key)
        }
    }

    private func allSealedGrants() -> [SealedGrant] {
        mergedByID(
            (decode([SealedGrant].self, key: grantsKey) ?? [])
                + (decode([SealedGrant].self, key: fire1GrantsKey) ?? []),
            id: { $0.grant.triggerID }
        )
    }

    private func persistGrantPartitions(_ grants: [SealedGrant], rules: [TriggerRule]) {
        let fire1RuleIDs = Set(
            rules.lazy
                .filter { !$0.onEnter.isLegacyStorageCompatible }
                .map(\.id)
        )
        let legacy = grants.filter { sealed in
            !fire1RuleIDs.contains(sealed.grant.triggerID)
                && sealed.grant.allowedWriteSet.allSatisfy { !$0.item.isExact }
        }
        let legacyIDs = Set(legacy.map { $0.grant.triggerID })
        let fire1 = grants.filter { !legacyIDs.contains($0.grant.triggerID) }
        persist(legacy, key: grantsKey)
        persist(fire1, key: fire1GrantsKey)
    }

    private func persist<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func mergedByID(_ values: [TriggerRule]) -> [TriggerRule] {
        mergedByID(values, id: \TriggerRule.id)
    }

    private func mergedByID<Value, ID: Hashable>(
        _ values: [Value],
        id: (Value) -> ID
    ) -> [Value] {
        var seen = Set<ID>()
        return values.reversed().filter { seen.insert(id($0)).inserted }.reversed()
    }

    private func decode<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
