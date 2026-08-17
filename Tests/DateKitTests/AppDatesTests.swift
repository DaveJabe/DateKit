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

    /// A calendar pinned to an explicit (usually DST-observing) zone, for
    /// day-boundary correctness tests that must not depend on the runner's zone.
    private func calendar(zone identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    /// A date at the given Y-M-D h:m in the supplied fixed-zone calendar.
    private func date(_ calendar: Calendar, _ year: Int, _ month: Int, _ day: Int,
                      _ hour: Int = 0, _ minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day
        components.hour = hour; components.minute = minute
        return calendar.date(from: components)!
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

    // MARK: daysBetween — days with no local midnight (midnight spring-forward)

    // Some zones spring forward AT midnight (America/Santiago, America/Havana,
    // Atlantic/Azores), so the transition day has no 00:00 and `startOfDay` lands
    // on 01:00. Whole-day differencing must still count real calendar days —
    // midnight-floored math is one day short for every span touching that day.

    func testDaysBetweenAcrossMidnightSpringForwardCountsCalendarDays() {
        // Chile: Sun Sep 7 2025 starts at 01:00 (00:00–00:59 does not exist).
        let santiago = calendar(zone: "America/Santiago")
        XCTAssertEqual(
            AppDates.daysBetween(
                date(santiago, 2025, 9, 7, 12, 0), date(santiago, 2025, 9, 8, 12, 0),
                calendar: santiago
            ),
            1,
            "the midnight-less transition day to the next day is one calendar day"
        )
        XCTAssertEqual(
            AppDates.daysBetween(
                date(santiago, 2025, 9, 7, 12, 0), date(santiago, 2025, 12, 25, 12, 0),
                calendar: santiago
            ),
            109,
            "a long span anchored on the midnight-less day must not be one day short"
        )
    }

    func testDaysBetweenMidnightlessTransitionDayInHavanaAndAzores() {
        // Cuba: Sun Mar 9 2025 starts at 01:00. Azores: Sun Mar 30 2025 starts at 01:00.
        let havana = calendar(zone: "America/Havana")
        XCTAssertEqual(
            AppDates.daysBetween(
                date(havana, 2025, 3, 9, 12, 0), date(havana, 2025, 3, 10, 12, 0),
                calendar: havana
            ),
            1
        )
        let azores = calendar(zone: "Atlantic/Azores")
        XCTAssertEqual(
            AppDates.daysBetween(
                date(azores, 2025, 3, 30, 12, 0), date(azores, 2025, 3, 31, 12, 0),
                calendar: azores
            ),
            1
        )
    }

    // MARK: daysBetween across ordinary (02:00) DST transitions

    func testDaysBetweenAcrossSpringForwardCountsCalendarDays() {
        // US spring-forward (Mar 9 2025, 02:00): only 23 hours between those two
        // midnights, yet Mar 8 → Mar 10 is two calendar days — never floor(47/24).
        let newYork = calendar(zone: "America/New_York")
        let start = date(newYork, 2025, 3, 8, 18, 0)
        let end = date(newYork, 2025, 3, 10, 6, 0)
        XCTAssertEqual(AppDates.daysBetween(start, end, calendar: newYork), 2)
        XCTAssertEqual(
            AppDates.daysBetween(end, start, calendar: newYork), -2,
            "daysBetween stays signed across a DST transition"
        )
    }

    func testDaysBetweenAcrossFallBackCountsCalendarDays() {
        // US fall-back (Nov 2 2025): a 25-hour day must still count as one day.
        let newYork = calendar(zone: "America/New_York")
        let start = date(newYork, 2025, 11, 1, 12, 0)
        let end = date(newYork, 2025, 11, 3, 12, 0)
        XCTAssertEqual(AppDates.daysBetween(start, end, calendar: newYork), 2)
    }

    // MARK: timeSinceComponents

    func testTimeSinceComponentsAcrossMidnightSpringForwardIsOneDay() {
        // Same midnight-less day as above: 10:00 → next-day 09:00 is only 22 real
        // hours, but it spans two calendar days → Y/M/D path with days == 1, not
        // an HMS result.
        let santiago = calendar(zone: "America/Santiago")
        let result = AppDates.timeSinceComponents(
            from: date(santiago, 2025, 9, 7, 10, 0),
            to: date(santiago, 2025, 9, 8, 9, 0),
            calendar: santiago
        )
        XCTAssertEqual(result, TimeSinceComponents(years: 0, months: 0, days: 1))
    }

    func testTimeSinceComponentsSubDayCarriesHMS() {
        let result = AppDates.timeSinceComponents(
            from: utc(2025, 1, 1, 0, 0, 0), to: utc(2025, 1, 1, 3, 4, 5), calendar: utcCalendar
        )
        XCTAssertEqual(result, TimeSinceComponents(years: 0, months: 0, days: 0, hours: 3, minutes: 4, seconds: 5))
    }

    func testTimeSinceComponentsStraddlingMidnightIsOneDay() {
        // Only 90 minutes apart, but the instants sit on different calendar days,
        // so the Y/M/D path wins with days == 1 — never an HMS result. This is the
        // documented contrast with ElapsedTimeBreakdown's whole-24h counting.
        let result = AppDates.timeSinceComponents(
            from: utc(2025, 6, 1, 23, 0), to: utc(2025, 6, 2, 0, 30), calendar: utcCalendar
        )
        XCTAssertEqual(result, TimeSinceComponents(years: 0, months: 0, days: 1))
    }

    func testTimeSinceComponentsLeapDayStartClampsAnniversary() {
        // Feb 29 starts: the missing anniversary clamps to Feb 28 (exactly 1 year),
        // and Mar 1 is one day past it — mirroring ElapsedTimeBreakdown.compute.
        let toFeb28 = AppDates.timeSinceComponents(
            from: utc(2024, 2, 29), to: utc(2025, 2, 28), calendar: utcCalendar
        )
        XCTAssertEqual(toFeb28, TimeSinceComponents(years: 1, months: 0, days: 0))

        let toMar1 = AppDates.timeSinceComponents(
            from: utc(2024, 2, 29), to: utc(2025, 3, 1), calendar: utcCalendar
        )
        XCTAssertEqual(toMar1, TimeSinceComponents(years: 1, months: 0, days: 1))
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

    func testClockComponentsHugeFiniteIntervalClampsWithoutTrapping() {
        // Finite intervals beyond Int.max seconds must clamp (the helper is
        // documented as non-trapping and clamped), never trap in `Int(_:)`.
        for interval in [1e19, TimeInterval.greatestFiniteMagnitude] {
            let parts = AppDates.clockComponents(from: interval)
            XCTAssertEqual(parts.hours, Int.max / 3600)
            XCTAssertEqual(parts.minutes, (Int.max % 3600) / 60)
            XCTAssertEqual(parts.seconds, Int.max % 60)
        }
    }

    func testClockComponentsExtremeDateSpansClampWithoutTrapping() {
        // A distant-past start overflows Int when measured to now → clamps high;
        // a distant-future start yields a hugely negative interval → clamps to 0.
        let distantPast = Date(timeIntervalSinceReferenceDate: -1e300)
        let farForward = AppDates.clockComponents(since: distantPast, to: Date())
        XCTAssertEqual(farForward.hours, Int.max / 3600)

        let distantFuture = Date(timeIntervalSinceReferenceDate: 1e300)
        let reversed = AppDates.clockComponents(since: distantFuture, to: Date(timeIntervalSinceReferenceDate: 0))
        XCTAssertEqual(reversed.hours, 0)
        XCTAssertEqual(reversed.minutes, 0)
        XCTAssertEqual(reversed.seconds, 0)
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
