//
//  TriggerNarratorTests.swift
//  FireLogicTests
//

import XCTest
@testable import FireLogic

final class TriggerNarratorTests: XCTestCase {
    func testQuotaContextDescriptionIncludesFirelinePayloadWithoutMoves() {
        let action = TriggerAction.activateContext(
            ContextSceneAction(moves: [], fireline: .quota(.codex))
        )

        XCTAssertEqual(
            TriggerNarrator.describe(action),
            "show Codex limits in Fireline"
        )
    }

    func testInstallDescriptionDisclosesConditionAndFirelinePayload() {
        let rule = TriggerRule(
            name: "Coding",
            condition: .appFocus(bundleID: "com.openai.codex", state: .active),
            onEnter: .activateContext(
                ContextSceneAction(moves: [], fireline: .quota(.codex))
            )
        )

        XCTAssertEqual(TriggerNarrator.capabilityName(rule.onEnter), "Context Scene")
        XCTAssertEqual(
            TriggerNarrator.installDescription(rule),
            """
            Coding

            When “com.openai.codex” becomes the frontmost app, Fire will show Codex limits in Fireline.

            This Context Scene can then run without asking again. Any change to its condition, items, destination, or Fireline payload requires your approval again.
            """
        )
    }

    func testMailContextDescriptionIncludesExactMoveAndHiddenFireline() {
        let fantastical = ItemIdentity(
            bundleID: "85C27NK92C.com.flexibits.fantastical2.mac.helper",
            namespace: "85C27NK92C.com.flexibits.fantastical2.mac.helper",
            title: "Fantastical"
        )
        let action = TriggerAction.activateContext(
            ContextSceneAction(
                moves: [MovePlan(item: fantastical, toSection: .alwaysVisible)],
                fireline: .hidden
            )
        )

        XCTAssertEqual(
            TriggerNarrator.describe(action),
            "move “Fantastical” (85C27NK92C.com.flexibits.fantastical2.mac.helper) to the always-visible area; hide Fireline"
        )
    }
}
