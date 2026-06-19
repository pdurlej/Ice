//
//  AutomationGrant.swift
//  Ice
//
//  Tamper-evident authorization for AI-Native Triggers (fire.10 P1).
//
//  Per GPT-5.5 Pro's review: a trigger's "enabled" flag in UserDefaults is
//  NOT authority — a same-user process can edit defaults. Authority is a
//  sealed grant: HMAC-SHA256 over the canonical (condition + action + write
//  set), keyed by a secret kept in the Keychain (scoped to Fire by the default
//  access group). Any edit to the trigger changes the canonical digest, so the
//  old grant no longer validates ⇒ the trigger disables until re-approved.
//

import CryptoKit
import Foundation
import OSLog
import Security

// MARK: - Canonicalization

enum TriggerCanonicalizer {
    /// Deterministic SHA-256 over the security-relevant fields (condition +
    /// action + exact write set). Any change ⇒ a different digest ⇒ the grant
    /// stops validating, forcing re-approval.
    ///
    /// DETERMINISM (fire.10.3): the digest is built from `Canonical`, a flat
    /// representation that emits every Set as a SORTED array. The previous
    /// version encoded `TriggerCondition` directly, whose `.timeWindow` case
    /// holds a `Set<Weekday>` — and `Set` iterates in an order seeded randomly
    /// per process, while `.sortedKeys` only sorts object keys, not array
    /// elements. So a multi-day timeWindow rule produced a different digest on
    /// some launches, its sealed grant stopped matching, and the automation
    /// silently stopped firing. Sorting the days here makes the digest depend
    /// only on the rule's content, never on the runtime hash seed.
    static func digest(condition: TriggerCondition, action: TriggerAction) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes = (try? encoder.encode(Canonical(condition: condition, action: action))) ?? Data()
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    /// Flat, hash-seed-independent canonical form. Adding a field here changes
    /// every digest (and invalidates existing grants) — TriggerStore.load
    /// re-seals content-unchanged grants to absorb such a change.
    private struct Canonical: Codable {
        let condition: Cond
        let action: Act
        let writeSet: [Move]

        init(condition: TriggerCondition, action: TriggerAction) {
            self.condition = Cond(condition)
            self.action = Act(action)
            self.writeSet = action.writeSet.map(Move.init)
        }

        struct Cond: Codable {
            let kind: String
            var bundleID: String?
            var state: String?
            var percent: Int?
            var resetAbove: Int?
            var days: [Int]?
            var start: String?
            var end: String?
            var timeZoneID: String?

            init(_ condition: TriggerCondition) {
                switch condition {
                case .appFocus(let bundleID, let state):
                    kind = "appFocus"
                    self.bundleID = bundleID
                    self.state = state.rawValue
                case .batteryBelow(let percent, let resetAbove):
                    kind = "batteryBelow"
                    self.percent = percent
                    self.resetAbove = resetAbove
                case .timeWindow(let days, let start, let end, let timeZoneID):
                    kind = "timeWindow"
                    self.days = days.map(\.rawValue).sorted()
                    self.start = String(format: "%02d:%02d", start.hour, start.minute)
                    self.end = String(format: "%02d:%02d", end.hour, end.minute)
                    self.timeZoneID = timeZoneID
                }
            }
        }

        struct Act: Codable {
            let kind: String
            var section: String?
            var items: [String]?
            var layoutID: String?
            var layoutDigest: String?

            init(_ action: TriggerAction) {
                switch action {
                case .setSection(let items, let section):
                    kind = "setSection"
                    self.section = section.rawValue
                    self.items = items.map(\.bundleID)  // order-significant, as authored
                case .applyLayoutSnapshot(let layoutID, let layoutDigest, _):
                    kind = "applyLayoutSnapshot"
                    self.layoutID = layoutID.uuidString
                    self.layoutDigest = layoutDigest
                }
            }
        }

        struct Move: Codable {
            let bundleID: String
            let toSection: String
            init(_ move: MovePlan) {
                bundleID = move.bundleID
                toSection = move.toSection.rawValue
            }
        }
    }
}

// MARK: - Sealed grant

/// A grant plus its HMAC seal. Stored alongside the (untrusted) trigger config.
struct SealedGrant: Codable, Equatable {
    let grant: ApprovedAutomationGrant
    let mac: Data
}

// MARK: - Grant store

/// Seals and validates automation grants. The HMAC key lives in the Keychain;
/// a same-user *other* process can edit Ice's defaults but cannot forge a
/// valid seal without that key.
///
/// NOTE (P1 limitation): on ad-hoc-signed builds (no Apple team), Keychain
/// isolation is weaker. fire.10.2 closed the transport half of the follow-up:
/// the MCP path is peer-authenticated XPC end-to-end, so a forged grant can
/// no longer reach the mutation path from outside the app. The remaining
/// half — moving this key to the DataProtection keychain (signature-bound
/// ACL) — needs an app-identifier entitlement in the CI signing step first
/// (the app currently signs with no entitlements file, so
/// kSecUseDataProtectionKeychain would fail with errSecMissingEntitlement);
/// tracked, deliberately not shipped as dead code.
final class AutomationGrantStore {
    static let shared = AutomationGrantStore()

    private let service = "com.jordanbaird.Ice.automation"
    private let account = "grant-hmac-key-v1"
    private let logger = Logger(category: "AutomationGrantStore")

    private init() {}

    /// Seals a grant under the Keychain key. Returns nil only if the key is
    /// unavailable.
    func seal(_ grant: ApprovedAutomationGrant) -> SealedGrant? {
        guard let key = hmacKey() else {
            logger.error("Cannot seal grant: HMAC key unavailable")
            return nil
        }
        return Self.seal(grant, key: key)
    }

    /// True only if the seal matches the grant under the Keychain key.
    func validates(_ sealed: SealedGrant) -> Bool {
        guard let key = hmacKey() else { return false }
        return Self.validates(sealed, key: key)
    }

    // MARK: Pure, key-injected core (unit-testable without the Keychain)

    /// Seals a grant with an explicit key. The crypto + canonical encoding live
    /// here so tests exercise the real seal/validate path with a fixed key.
    static func seal(_ grant: ApprovedAutomationGrant, key: SymmetricKey) -> SealedGrant? {
        guard let bytes = encode(grant) else { return nil }
        let mac = HMAC<SHA256>.authenticationCode(for: bytes, using: key)
        return SealedGrant(grant: grant, mac: Data(mac))
    }

    /// Constant-time check (via CryptoKit) that `sealed` was sealed with `key`.
    static func validates(_ sealed: SealedGrant, key: SymmetricKey) -> Bool {
        guard let bytes = encode(sealed.grant) else { return false }
        return HMAC<SHA256>.isValidAuthenticationCode(sealed.mac, authenticating: bytes, using: key)
    }

    private static func encode(_ grant: ApprovedAutomationGrant) -> Data? {
        // Keep the DEFAULT date strategy: `Date` encodes as a deterministic
        // Double (timeIntervalSinceReferenceDate), and changing it would alter
        // the MAC'd bytes and invalidate every existing grant — which would in
        // turn break the re-seal migration that relies on the old MAC still
        // validating. Only `.sortedKeys` (stable key order) is needed.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(grant)
    }

    // MARK: Keychain-backed HMAC key

    /// Returns the HMAC key, generating and storing a random 256-bit key on
    /// first use.
    private func hmacKey() -> SymmetricKey? {
        if let existing = loadKey() {
            return existing
        }
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        storeKey(data)
        return key
    }

    private func loadKey() -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return SymmetricKey(data: data)
    }

    private func storeKey(_ data: Data) {
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemDelete(attributes as CFDictionary)
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status != errSecSuccess {
            logger.error("Failed to store automation HMAC key: status \(status)")
        }
    }
}
