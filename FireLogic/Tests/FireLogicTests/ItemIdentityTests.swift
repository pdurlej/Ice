//
//  ItemIdentityTests.swift
//  FireLogicTests
//

import XCTest
@testable import FireLogic

final class ItemIdentityTests: XCTestCase {
    func testLegacyMovePlanRoundTripsInLegacyShape() throws {
        let move = MovePlan(bundleID: "com.flexibits.fantastical2.mac", toSection: .alwaysVisible)
        let data = try JSONEncoder().encode(move)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["bundleID"] as? String, "com.flexibits.fantastical2.mac")
        XCTAssertNil(object["item"])
        XCTAssertEqual(try JSONDecoder().decode(MovePlan.self, from: data), move)
    }

    func testExactMovePlanRoundTripsWithSelector() throws {
        let identity = ItemIdentity(
            bundleID: "com.flexibits.fantastical2.mac",
            namespace: "com.flexibits.fantastical2.mac",
            title: "Fantastical"
        )
        let move = MovePlan(item: identity, toSection: .alwaysVisible)
        let data = try JSONEncoder().encode(move)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertNotNil(object["item"])
        XCTAssertNil(object["bundleID"])
        XCTAssertEqual(try JSONDecoder().decode(MovePlan.self, from: data), move)
    }

    func testExactIdentityChangesCanonicalDigest() {
        let condition = TriggerCondition.appFocus(bundleID: "com.apple.mail", state: .active)
        let legacy = TriggerAction.setSection(
            items: [ItemIdentity(bundleID: "com.flexibits.fantastical2.mac")],
            section: .alwaysVisible
        )
        let exact = TriggerAction.setSection(
            items: [ItemIdentity(
                bundleID: "com.flexibits.fantastical2.mac",
                namespace: "com.flexibits.fantastical2.mac",
                title: "Fantastical"
            )],
            section: .alwaysVisible
        )

        XCTAssertNotEqual(
            TriggerCanonicalizer.digest(condition: condition, action: legacy),
            TriggerCanonicalizer.digest(condition: condition, action: exact)
        )
    }

    func testOnlyLegacyIdentityActionsStayInRollbackCompatibleStorage() {
        let legacy = TriggerAction.setSection(
            items: [ItemIdentity(bundleID: "com.example.mail")],
            section: .alwaysVisible
        )
        let exact = TriggerAction.setSection(
            items: [ItemIdentity(bundleID: "com.example.mail", namespace: "42", title: "Calendar")],
            section: .alwaysVisible
        )
        let context = TriggerAction.activateContext(
            ContextSceneAction(moves: [], fireline: .quota(.codex))
        )

        XCTAssertTrue(legacy.isLegacyStorageCompatible)
        XCTAssertFalse(exact.isLegacyStorageCompatible)
        XCTAssertFalse(context.isLegacyStorageCompatible)
    }
}
