//
//  CanonicalizerTests.swift
//  FireLogicTests
//
//  The digest is the linchpin of tamper-evidence: it must depend ONLY on a
//  trigger's content, never on the process hash seed. The golden values pin the
//  canonical form — a regression to encoding a `Set<Weekday>` directly (the
//  fire.10.2 bug) is hash-seed-dependent and would make these goldens flake.
//

import XCTest
@testable import FireLogic

final class CanonicalizerTests: XCTestCase {
    private let appFocus = TriggerCondition.appFocus(bundleID: "com.tinyspeck.slackmacgap", state: .active)
    private let battery = TriggerCondition.batteryBelow(percent: 20, resetAbove: 30)
    private let action = TriggerAction.setSection(
        items: [ItemIdentity(bundleID: "com.bitwarden.desktop")],
        section: .hidden
    )

    private func timeWindow(_ days: Set<Weekday>) -> TriggerCondition {
        .timeWindow(days: days, start: LocalTime(hour: 9, minute: 0), end: LocalTime(hour: 17, minute: 0), timeZoneID: "Europe/Warsaw")
    }

    func testStableAcrossCalls() {
        XCTAssertEqual(
            TriggerCanonicalizer.digest(condition: appFocus, action: action),
            TriggerCanonicalizer.digest(condition: appFocus, action: action)
        )
    }

    func testDayOrderInvariant() {
        let a = TriggerCanonicalizer.digest(condition: timeWindow([.monday, .wednesday, .friday]), action: action)
        let b = TriggerCanonicalizer.digest(condition: timeWindow([.friday, .monday, .wednesday]), action: action)
        XCTAssertEqual(a, b)
    }

    func testDistinguishesContent() {
        let base = TriggerCanonicalizer.digest(condition: battery, action: action)
        XCTAssertNotEqual(base, TriggerCanonicalizer.digest(condition: .batteryBelow(percent: 25, resetAbove: 30), action: action))
        XCTAssertNotEqual(base, TriggerCanonicalizer.digest(condition: appFocus, action: action))
        XCTAssertNotEqual(
            TriggerCanonicalizer.digest(condition: timeWindow([.monday]), action: action),
            TriggerCanonicalizer.digest(condition: timeWindow([.monday, .tuesday]), action: action)
        )
    }

    // Goldens — bootstrapped on first green run (see GOLDEN markers).
    func testGoldenAppFocus() {
        XCTAssertEqual(TriggerCanonicalizer.digest(condition: appFocus, action: action), "4386de70f8e412642b0502d46d23b12031a7cfacbb1355a3b0463d27d4a6000d")
    }
    func testGoldenBattery() {
        XCTAssertEqual(TriggerCanonicalizer.digest(condition: battery, action: action), "718aadc3dc4060c32779613b7ff278b3d236eb3c38d8f44b76c3d3103d9b1f3b")
    }
    func testGoldenTimeWindow() {
        XCTAssertEqual(TriggerCanonicalizer.digest(condition: timeWindow([.monday, .wednesday, .friday]), action: action), "888eb2747da8acf2975743612f6756102470e7f7cb80503b1d4fb05da1fe3c34")
    }
}
