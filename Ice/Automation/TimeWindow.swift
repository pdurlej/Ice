//
//  TimeWindow.swift
//  Ice
//
//  Pure, Foundation-only time-window evaluation for AI-Native Triggers
//  (extracted verbatim from TriggerEngine.isInWindow in fire.10.3 so it can be
//  unit-tested with `swift test` — no AppKit, no live clock). The engine calls
//  `TimeWindow.contains(now:)`; tests inject `now` and a timezone to cover
//  midnight-crossing, day-membership, and DST edges deterministically.
//
//  Behavior is identical to the previous inline implementation: the window is
//  half-open [start, end); a window whose end is strictly before start crosses
//  midnight. (start == end never matches — and is rejected at install time by
//  TriggerSpecTranslator.)
//

import Foundation

enum TimeWindow {
    static func contains(
        days: Set<Weekday>,
        start: LocalTime,
        end: LocalTime,
        timeZoneID: String,
        now: Date
    ) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneID) ?? .current
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: now)
        guard
            let weekdayValue = components.weekday,
            let weekday = Weekday(rawValue: weekdayValue),
            days.contains(weekday),
            let hour = components.hour,
            let minute = components.minute
        else {
            return false
        }
        let nowMinutes = hour * 60 + minute
        let startMinutes = start.hour * 60 + start.minute
        let endMinutes = end.hour * 60 + end.minute
        if startMinutes <= endMinutes {
            return nowMinutes >= startMinutes && nowMinutes < endMinutes
        }
        return nowMinutes >= startMinutes || nowMinutes < endMinutes  // crosses midnight
    }
}
