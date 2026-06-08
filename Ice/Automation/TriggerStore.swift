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
final class TriggerStore {
    static let shared = TriggerStore()

    private let rulesKey = "Triggers"
    private let grantsKey = "TriggerGrants"
    private let logger = Logger(category: "TriggerStore")

    private init() {}

    /// The current rules. Mutated only through this store so persistence and
    /// grant validation stay in lockstep.
    private(set) var rules: [TriggerRule] = []

    /// Loads rules from defaults and validates each enabled rule's sealed
    /// grant, disabling any that fail.
    func load() {
        let storedRules = decode([TriggerRule].self, key: rulesKey) ?? []
        let sealedGrants = decode([SealedGrant].self, key: grantsKey) ?? []
        let grantByTrigger = Dictionary(
            sealedGrants.map { ($0.grant.triggerID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        rules = storedRules.map { rule in
            guard rule.enabled else { return rule }
            guard
                let sealed = grantByTrigger[rule.id],
                sealed.grant.generation == rule.generation,
                AutomationGrantStore.shared.validates(sealed)
            else {
                logger.warning("Trigger \(rule.id, privacy: .public) disabled: grant missing/stale/tampered")
                var disabled = rule
                disabled.enabled = false
                return disabled
            }
            return rule
        }
        if rules != storedRules {
            persistRules()  // write back the force-disables
        }
        logger.debug("Loaded \(self.rules.count) trigger(s)")
    }

    /// Inserts or replaces a rule and (optionally) its sealed grant.
    func upsert(_ rule: TriggerRule, grant: SealedGrant?) {
        rules.removeAll { $0.id == rule.id }
        rules.append(rule)
        persistRules()
        if let grant {
            persistGrant(grant)
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
            let grants = decode([SealedGrant].self, key: grantsKey) ?? []
            guard
                let sealed = grants.first(where: { $0.grant.triggerID == id }),
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
        let all = decode([SealedGrant].self, key: grantsKey) ?? []
        return all.first { $0.grant.triggerID == id }
    }

    // MARK: Persistence

    private func persistRules() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(rules) {
            UserDefaults.standard.set(data, forKey: rulesKey)
        }
    }

    private func persistGrant(_ sealed: SealedGrant) {
        var all = decode([SealedGrant].self, key: grantsKey) ?? []
        all.removeAll { $0.grant.triggerID == sealed.grant.triggerID }
        all.append(sealed)
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: grantsKey)
        }
    }

    private func removeGrant(triggerID: UUID) {
        var all = decode([SealedGrant].self, key: grantsKey) ?? []
        all.removeAll { $0.grant.triggerID == triggerID }
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: grantsKey)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
