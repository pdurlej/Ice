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
    static func digest(condition: TriggerCondition, action: TriggerAction) -> String {
        struct Canonical: Codable {
            let condition: TriggerCondition
            let action: TriggerAction
            let writeSet: [MovePlan]
        }
        let canonical = Canonical(condition: condition, action: action, writeSet: action.writeSet)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes = (try? encoder.encode(canonical)) ?? Data()
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
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
/// isolation is weaker. The stronger boundary — a Keychain access policy tied
/// to Fire's code signature, and peer-authenticated XPC — is the tracked
/// follow-up.
final class AutomationGrantStore {
    static let shared = AutomationGrantStore()

    private let service = "com.jordanbaird.Ice.automation"
    private let account = "grant-hmac-key-v1"
    private let logger = Logger(category: "AutomationGrantStore")

    private init() {}

    /// Seals a grant. Returns nil only if the Keychain key is unavailable.
    func seal(_ grant: ApprovedAutomationGrant) -> SealedGrant? {
        guard let key = hmacKey(), let bytes = encode(grant) else {
            logger.error("Cannot seal grant: HMAC key or encoding unavailable")
            return nil
        }
        let mac = HMAC<SHA256>.authenticationCode(for: bytes, using: key)
        return SealedGrant(grant: grant, mac: Data(mac))
    }

    /// True only if the seal matches the grant under the Keychain key
    /// (constant-time comparison via CryptoKit).
    func validates(_ sealed: SealedGrant) -> Bool {
        guard let key = hmacKey(), let bytes = encode(sealed.grant) else {
            return false
        }
        return HMAC<SHA256>.isValidAuthenticationCode(sealed.mac, authenticating: bytes, using: key)
    }

    private func encode(_ grant: ApprovedAutomationGrant) -> Data? {
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
