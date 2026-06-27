//
//  AppDatesTests.swift
//  DateKitTests
//
//  Deterministic coverage of the agnostic AppDates helpers. `daysBetween`,
//  `timeSinceComponents`, and `isMidnight` are exercised against an explicit UTC
//  calendar; `compactElapsed` is asserted via locale-independent properties
//  because its formatter reads the current locale/time zone.
//

import XCTest
@testable import DateKit

final class AppDatesTests: XCTestCase {

    private let utcCalendar = ElapsedTimeBreakdown.utcCalendar

    private func utc(_ year: Int, _ month: Int, _ day: Int,
                     _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day
        components.hour = hour; components.minute = minute; components.second = second
        return utcCalendar.date(from: components)!
    }

    // MARK: daysBetween (calendar-midnight floored)

    func testDaysBetweenSameCalendarDayIsZero() {
        // Different times of the SAME calendar day floor to the same midnight → 0.
        let result = AppDates.daysBetween(
            utc(2025, 6, 1, 1, 0), utc(2025, 6, 1, 23, 0), calendar: utcCalendar
        )
        XCTAssertEqual(result, 0)
    }

    func testDaysBetweenCrossingMidnightIsOne() {
        // Only 1.5 hours apart, but they straddle midnight → one calendar day.
        // (Contrast with ElapsedTimeBreakdown, which counts whole 24h periods.)
        let result = AppDates.daysBetween(
            utc(2025, 6, 1, 23, 0), utc(2025, 6, 2, 0, 30), calendar: utcCalendar
        )
        XCTAssertEqual(result, 1)
    }

    func testDaysBetweenOneWeek() {
        let result = AppDates.daysBetween(
            utc(2025, 6, 1), utc(2025, 6, 8), calendar: utcCalendar
        )
        XCTAssertEqual(result, 7)
    }

    func testDaysBetweenIsSignedWhenReversed() {
        let result = AppDates.daysBetween(
            utc(2025, 6, 8), utc(2025, 6, 1), calendar: utcCalendar
        )
        XCTAssertEqual(result, -7)
    }

    // MARK: timeSinceComponents

    func testTimeSinceComponentsSubDayCarriesHMS() {
        let result = AppDates.timeSinceComponents(
            from: utc(2025, 1, 1, 0, 0, 0), to: utc(2025, 1, 1, 3, 4, 5), calendar: utcCalendar
        )
        XCTAssertEqual(result, TimeSinceComponents(years: 0, months: 0, days: 0, hours: 3, minutes: 4, seconds: 5))
    }

    func testTimeSinceComponentsMultiDayIsYMD() {
        let result = AppDates.timeSinceComponents(
            from: utc(2025, 1, 1), to: utc(2025, 3, 5), calendar: utcCalendar
        )
        XCTAssertEqual(result.years, 0)
        XCTAssertEqual(result.months, 2)
        XCTAssertEqual(result.days, 4)
        XCTAssertEqual(result.hours, 0)
        XCTAssertEqual(result.minutes, 0)
        XCTAssertEqual(result.seconds, 0)
    }

    // MARK: isMidnight

    func testIsMidnightTrueAtExactMidnight() {
        XCTAssertTrue(AppDates.isMidnight(utc(2025, 6, 1, 0, 0, 0), calendar: utcCalendar))
    }

    func testIsMidnightFalseJustAfterMidnight() {
        XCTAssertFalse(AppDates.isMidnight(utc(2025, 6, 1, 0, 0, 30), calendar: utcCalendar))
    }

    // MARK: clockComponents

    func testClockComponentsSplitsInterval() {
        let parts = AppDates.clockComponents(from: 3661) // 1h 1m 1s
        XCTAssertEqual(parts.hours, 1)
        XCTAssertEqual(parts.minutes, 1)
        XCTAssertEqual(parts.seconds, 1)
    }

    func testClockComponentsClampsNegative() {
        let parts = AppDates.clockComponents(from: -42)
        XCTAssertEqual(parts.hours, 0)
        XCTAssertEqual(parts.minutes, 0)
        XCTAssertEqual(parts.seconds, 0)
    }

    func testClockComponentsBetweenDates() {
        let start = utc(2025, 6, 1, 0, 0, 0)
        let end = utc(2025, 6, 1, 2, 2, 5) // +7325s
        let parts = AppDates.clockComponents(since: start, to: end)
        XCTAssertEqual(parts.hours, 2)
        XCTAssertEqual(parts.minutes, 2)
        XCTAssertEqual(parts.seconds, 5)
    }

    // MARK: compactElapsed (locale-independent properties)

    func testCompactElapsedIsNonEmptyForZeroSpan() {
        let instant = utc(2025, 6, 1, 12, 0)
        let result = AppDates.compactElapsed(from: instant, to: instant)
        XCTAssertFalse(result.isEmpty)
        XCTAssertTrue(result.contains(where: \.isNumber))
    }

    func testCompactElapsedIsNonEmptyForMultiYearSpan() {
        let result = AppDates.compactElapsed(from: utc(2021, 1, 1), to: utc(2025, 3, 4))
        XCTAssertFalse(result.isEmpty)
        XCTAssertTrue(result.contains(where: \.isNumber))
    }

    func testCompactElapsedIsSymmetric() {
        let early = utc(2022, 5, 10)
        let late = utc(2025, 8, 19)
        XCTAssertEqual(
            AppDates.compactElapsed(from: early, to: late),
            AppDates.compactElapsed(from: late, to: early)
        )
    }

    // MARK: dateString / dateTimeString smoke (non-empty across locales)

    func testDateStringIsNonEmpty() {
        let value = AppDates.dateString(utc(2025, 6, 15), style: .long)
        XCTAssertFalse(value.isEmpty)
    }

    func testAppDateStyleHasThreeCases() {
        XCTAssertEqual(AppDateStyle.allCases.count, 3)
        XCTAssertEqual(AppDateStyle.short.id, "short")
    }

    // MARK: timeSinceComponents — years path & symmetry (DK-5, DK-3)

    func testTimeSinceComponentsMultiYearIsYMD() {
        // 2021-01-01 → 2025-03-04 is exactly 4 years, 2 months, 3 days.
        let result = AppDates.timeSinceComponents(
            from: utc(2021, 1, 1), to: utc(2025, 3, 4), calendar: utcCalendar
        )
        XCTAssertEqual(result, TimeSinceComponents(years: 4, months: 2, days: 3))
    }

    func testTimeSinceComponentsReversedSubDayMatchesForward() {
        // Reversed same-day input yields the same magnitude as forward input.
        let forward = AppDates.timeSinceComponents(
            from: utc(2025, 1, 1, 10, 0, 0), to: utc(2025, 1, 1, 15, 0, 0), calendar: utcCalendar
        )
        let reversed = AppDates.timeSinceComponents(
            from: utc(2025, 1, 1, 15, 0, 0), to: utc(2025, 1, 1, 10, 0, 0), calendar: utcCalendar
        )
        XCTAssertEqual(forward, TimeSinceComponents(years: 0, months: 0, days: 0, hours: 5, minutes: 0, seconds: 0))
        XCTAssertEqual(reversed, forward)
    }

    func testTimeSinceComponentsReversedMultiDayMatchesForward() {
        let forward = AppDates.timeSinceComponents(
            from: utc(2021, 1, 1), to: utc(2025, 3, 4), calendar: utcCalendar
        )
        let reversed = AppDates.timeSinceComponents(
            from: utc(2025, 3, 4), to: utc(2021, 1, 1), calendar: utcCalendar
        )
        XCTAssertEqual(reversed, forward)
    }

    // MARK: dateTimeString (DK-2)

    /// Local midnight today, built in the same autoupdating calendar that
    /// `dateTimeString` uses internally, so `isMidnight` is true regardless of the
    /// runner's time zone.
    private var localMidnight: Date {
        Calendar.autoupdatingCurrent.startOfDay(for: Date())
    }

    func testDateTimeStringAtMidnightEqualsDateString() {
        for style in AppDateStyle.allCases {
            XCTAssertEqual(
                AppDates.dateTimeString(localMidnight, dateStyle: style),
                AppDates.dateString(localMidnight, style: style),
                "midnight must short-circuit to the date-only string for \(style.id)"
            )
        }
    }

    func testDateTimeStringNonMidnightAddsTimeComponent() {
        let afternoon = localMidnight.addingTimeInterval(15 * 3600 + 45 * 60) // 15:45 local
        for style in AppDateStyle.allCases {
            let withTime = AppDates.dateTimeString(afternoon, dateStyle: style)
            let dateOnly = AppDates.dateString(afternoon, style: style)
            XCTAssertFalse(withTime.isEmpty)
            XCTAssertTrue(withTime.contains(where: \.isNumber))
            XCTAssertNotEqual(withTime, dateOnly, "non-midnight must add a time component for \(style.id)")
        }
    }

    // MARK: AppDateStyle → DateStyle mapping (DK-4)

    func testDateStringIsNonEmptyAndDistinctAcrossStyles() {
        let date = utc(2025, 6, 15)
        var rendered: [String] = []
        for style in AppDateStyle.allCases {
            let value = AppDates.dateString(date, style: style)
            XCTAssertFalse(value.isEmpty)
            XCTAssertTrue(value.contains(where: \.isNumber), "\(style.id) should contain a numeral")
            rendered.append(value)
        }
        // .short(.numeric) / .medium(.abbreviated) / .long(.complete) are distinct
        // formats — a regression that collapsed or swapped two arms would tie them.
        XCTAssertEqual(Set(rendered).count, AppDateStyle.allCases.count)
    }

    // MARK: isMidnight sub-second policy (DK-7)

    func testIsMidnightFalseWithFractionalSecond() {
        let justAfterMidnight = utc(2025, 6, 1, 0, 0, 0).addingTimeInterval(0.5)
        XCTAssertFalse(AppDates.isMidnight(justAfterMidnight, calendar: utcCalendar))
    }

    // MARK: clockComponents non-finite guard (DK-8) & reversed dates (DK-12)

    func testClockComponentsInfinityIsZero() {
        let parts = AppDates.clockComponents(from: .infinity)
        XCTAssertEqual(parts.hours, 0)
        XCTAssertEqual(parts.minutes, 0)
        XCTAssertEqual(parts.seconds, 0)
    }

    func testClockComponentsNegativeInfinityIsZero() {
        let parts = AppDates.clockComponents(from: -.infinity)
        XCTAssertEqual(parts.hours, 0)
        XCTAssertEqual(parts.minutes, 0)
        XCTAssertEqual(parts.seconds, 0)
    }

    func testClockComponentsNaNIsZero() {
        let parts = AppDates.clockComponents(from: .nan)
        XCTAssertEqual(parts.hours, 0)
        XCTAssertEqual(parts.minutes, 0)
        XCTAssertEqual(parts.seconds, 0)
    }

    func testClockComponentsReversedDatesAreZero() {
        let start = utc(2025, 6, 1, 5, 0, 0)
        let now = utc(2025, 6, 1, 2, 0, 0) // earlier than start
        let parts = AppDates.clockComponents(since: start, to: now)
        XCTAssertEqual(parts.hours, 0)
        XCTAssertEqual(parts.minutes, 0)
        XCTAssertEqual(parts.seconds, 0)
    }

    // MARK: compactElapsed unit count & sub-day fallback (DK-11)

    /// The number of distinct digit runs in a string — one per displayed unit.
    private func numericGroupCount(_ string: String) -> Int {
        string.split(whereSeparator: { !$0.isNumber }).count
    }

    func testCompactElapsedShowsAtMostTwoUnits() {
        // 4y 2m 3d has three non-zero units; maximumUnitCount == 2 drops the third.
        let result = AppDates.compactElapsed(from: utc(2021, 1, 1), to: utc(2025, 3, 4))
        XCTAssertGreaterThanOrEqual(numericGroupCount(result), 1)
        XCTAssertLessThanOrEqual(numericGroupCount(result), 2)
    }

    func testCompactElapsedSubDaySpanFallsBackToDayCount() {
        // A 5-hour span has zero whole years/months/days, so the primary formatter
        // drops everything and the day fallback produces a localized "0 day" string.
        let instant = utc(2025, 6, 1, 9, 0, 0)
        let result = AppDates.compactElapsed(from: instant, to: instant.addingTimeInterval(5 * 3600))
        XCTAssertFalse(result.isEmpty)
        XCTAssertTrue(result.contains("0"))
    }

    // MARK: Default-argument paths & AppDates.calendar (DK-10)

    func testDefaultCalendarPathsRunWithoutTrapping() {
        let start = utc(2025, 1, 1)
        let end = utc(2025, 6, 1)
        // No explicit calendar → exercises the AppDates.calendar default binding.
        _ = AppDates.daysBetween(start, end)
        let since = AppDates.timeSinceComponents(from: start, to: end)
        XCTAssertGreaterThanOrEqual(since.years, 0)
        XCTAssertGreaterThanOrEqual(since.months, 0)
    }

    func testComputeDefaultCalendarIsNonNegative() {
        let breakdown = ElapsedTimeBreakdown.compute(from: utc(2025, 1, 1), to: utc(2025, 6, 1))
        XCTAssertGreaterThanOrEqual(breakdown.totalDays, 0)
        XCTAssertGreaterThanOrEqual(breakdown.years, 0)
    }

    func testCompactElapsedDefaultToIsNonEmpty() {
        // No `to` → defaults to Date(); a long-ago start always yields a real span.
        let result = AppDates.compactElapsed(from: utc(2000, 1, 1))
        XCTAssertFalse(result.isEmpty)
        XCTAssertTrue(result.contains(where: \.isNumber))
    }

    func testAppDatesCalendarUsesAutoupdatingZone() {
        XCTAssertEqual(AppDates.calendar.timeZone.identifier, TimeZone.autoupdatingCurrent.identifier)
        XCTAssertNotNil(AppDates.calendar.locale)
    }
}
