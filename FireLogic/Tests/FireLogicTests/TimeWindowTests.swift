//
//  TimeWindowTests.swift
//  FireLogicTests
//
//  Half-open [start, end) weekly window, evaluated in a given IANA timezone.
//  Reference dates use June 2026, where the 15th is a Monday.
//

import XCTest
@testable import FireLogic

final class TimeWindowTests: XCTestCase {
    private let warsaw = "Europe/Warsaw"
    private let mondayOnly: Set<Weekday> = [.monday]

    /// A wall-clock instant on a given June-2026 day in `tz`.
    private func at(day: Int, _ hour: Int, _ minute: Int, tz: String? = nil) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: tz ?? warsaw)!
        return calendar.date(from: DateComponents(year: 2026, month: 6, day: day, hour: hour, minute: minute))!
    }

    private func inWindow(_ days: Set<Weekday>, _ s: (Int, Int), _ e: (Int, Int), _ now: Date, tz: String? = nil) -> Bool {
        TimeWindow.contains(
            days: days,
            start: LocalTime(hour: s.0, minute: s.1),
            end: LocalTime(hour: e.0, minute: e.1),
            timeZoneID: tz ?? warsaw,
            now: now
        )
    }

    func testInside() {
        XCTAssertTrue(inWindow(mondayOnly, (9, 0), (17, 0), at(day: 15, 10, 0)))
    }

    func testBeforeStart() {
        XCTAssertFalse(inWindow(mondayOnly, (9, 0), (17, 0), at(day: 15, 8, 0)))
    }

    func testEndIsExclusive() {
        XCTAssertFalse(inWindow(mondayOnly, (9, 0), (17, 0), at(day: 15, 17, 0)))
        XCTAssertTrue(inWindow(mondayOnly, (9, 0), (17, 0), at(day: 15, 16, 59)))
    }

    func testWrongWeekday() {
        // Tuesday the 16th, window is Monday-only.
        XCTAssertFalse(inWindow(mondayOnly, (9, 0), (17, 0), at(day: 16, 10, 0)))
    }

    func testMidnightCrossing() {
        // 22:00 -> 02:00 keyed to Monday's weekday.
        XCTAssertTrue(inWindow(mondayOnly, (22, 0), (2, 0), at(day: 15, 23, 0)))   // late Monday
        XCTAssertTrue(inWindow(mondayOnly, (22, 0), (2, 0), at(day: 15, 1, 0)))    // early Monday (before end)
        XCTAssertFalse(inWindow(mondayOnly, (22, 0), (2, 0), at(day: 15, 12, 0)))  // midday Monday
    }

    func testTimezoneIsHonored() {
        // Mon 23:30 in Warsaw is 21:30 UTC the same Monday.
        let instant = at(day: 15, 23, 30, tz: warsaw)
        XCTAssertTrue(inWindow(mondayOnly, (23, 0), (23, 59), instant, tz: warsaw))
        XCTAssertFalse(inWindow(mondayOnly, (23, 0), (23, 59), instant, tz: "UTC"))
    }
}
