//
//  GrantTests.swift
//  FireLogicTests
//
//  Seal/validate is the tamper-evidence that makes a trigger's authority real
//  (a same-user process can edit Ice's defaults but cannot forge a valid seal
//  without the Keychain key). These tests exercise the real crypto via the
//  key-injected static core.
//

import CryptoKit
import XCTest
@testable import FireLogic

final class GrantTests: XCTestCase {
    private func sampleGrant(digest: String = "deadbeef") -> ApprovedAutomationGrant {
        ApprovedAutomationGrant(
            triggerID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            generation: 1,
            canonicalDigest: digest,
            allowedWriteSet: [MovePlan(bundleID: "com.bitwarden.desktop", toSection: .hidden)],
            approvedAt: Date(timeIntervalSince1970: 1_700_000_000),
            approvedByFireVersion: "fire.10.3"
        )
    }

    func testSealValidateRoundtrip() {
        let key = SymmetricKey(size: .bits256)
        let sealed = AutomationGrantStore.seal(sampleGrant(), key: key)
        XCTAssertNotNil(sealed)
        XCTAssertTrue(AutomationGrantStore.validates(sealed!, key: key))
    }

    func testWrongKeyRejected() {
        let sealed = AutomationGrantStore.seal(sampleGrant(), key: SymmetricKey(size: .bits256))!
        XCTAssertFalse(AutomationGrantStore.validates(sealed, key: SymmetricKey(size: .bits256)))
    }

    func testTamperedMACRejected() {
        let key = SymmetricKey(size: .bits256)
        let sealed = AutomationGrantStore.seal(sampleGrant(), key: key)!
        var mac = sealed.mac
        mac[mac.startIndex] ^= 0xFF
        XCTAssertFalse(AutomationGrantStore.validates(SealedGrant(grant: sealed.grant, mac: mac), key: key))
    }

    func testTamperedGrantRejected() {
        // Swapping in a different grant (e.g. a widened write set or a forged
        // digest) under the original MAC must fail — the MAC covers the grant.
        let key = SymmetricKey(size: .bits256)
        let sealed = AutomationGrantStore.seal(sampleGrant(digest: "good"), key: key)!
        let forged = SealedGrant(grant: sampleGrant(digest: "EVIL"), mac: sealed.mac)
        XCTAssertFalse(AutomationGrantStore.validates(forged, key: key))
    }
}
