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
}
