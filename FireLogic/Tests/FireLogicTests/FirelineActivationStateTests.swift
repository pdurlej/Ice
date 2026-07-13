//
//  FirelineActivationStateTests.swift
//  FireLogicTests
//

import XCTest
@testable import FireLogic

final class FirelineActivationStateTests: XCTestCase {
    func testDeactivatesWhenActiveRuleWasRemovedEvenIfAnotherRuleIsEnabled() {
        let activeID = UUID()
        let other = makeRule(enabled: true)

        XCTAssertTrue(
            FirelineActivationState.shouldDeactivate(
                activeRuleID: activeID,
                rules: [other]
            )
        )
    }

    func testDeactivatesWhenActiveRuleWasDisabled() {
        let activeID = UUID()
        let active = makeRule(id: activeID, enabled: false)

        XCTAssertTrue(
            FirelineActivationState.shouldDeactivate(
                activeRuleID: activeID,
                rules: [active]
            )
        )
    }

    func testKeepsFirelineWhenActiveRuleRemainsEnabled() {
        let activeID = UUID()
        let active = makeRule(id: activeID, enabled: true)

        XCTAssertFalse(
            FirelineActivationState.shouldDeactivate(
                activeRuleID: activeID,
                rules: [active]
            )
        )
    }

    func testNoActiveRuleNeedsNoDeactivation() {
        XCTAssertFalse(
            FirelineActivationState.shouldDeactivate(
                activeRuleID: nil,
                rules: []
            )
        )
    }

    private func makeRule(id: UUID = UUID(), enabled: Bool) -> TriggerRule {
        TriggerRule(
            id: id,
            name: "Context",
            enabled: enabled,
            condition: .appFocus(bundleID: "com.example.app", state: .active),
            onEnter: .activateContext(
                ContextSceneAction(moves: [], fireline: .quota(.codex))
            )
        )
    }
}
