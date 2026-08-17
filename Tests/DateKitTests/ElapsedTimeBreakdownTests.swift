//
//  ElapsedTimeBreakdownTests.swift
//  DateKitTests
//
//  Deterministic coverage of the agnostic elapsed-time core. Every date is built
//  in a fixed calendar (UTC, or an explicit DST-observing zone) so results do not
//  depend on the machine's locale or time zone.
//

import XCTest
@testable import DateKit

final class ElapsedTimeBreakdownTests: XCTestCase {

    // MARK: Fixtures

    /// A date at the given Y-M-D h:m:s in the fixed UTC Gregorian calendar.
    private func utc(_ year: Int, _ month: Int, _ day: Int,
                     _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day
        components.hour = hour; components.minute = minute; components.second = second
        return ElapsedTimeBreakdown.utcCalendar.date(from: components)!
    }

    /// Shorthand for the fixed UTC calendar under test.
    private let utcCalendar = ElapsedTimeBreakdown.utcCalendar

    /// A calendar pinned to a DST-observing zone, for day-boundary correctness tests.
    private var newYorkCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    private func newYork(_ year: Int, _ month: Int, _ day: Int,
                         _ hour: Int = 0, _ minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day
        components.hour = hour; components.minute = minute
        return newYorkCalendar.date(from: components)!
    }

    // MARK: Basic intervals

    func testZeroIntervalIsAllZeros() {
        let instant = utc(2025, 6, 1, 9, 30, 0)
        let breakdown = ElapsedTimeBreakdown.compute(from: instant, to: instant, calendar: utcCalendar)
        XCTAssertEqual(breakdown, ElapsedTimeBreakdown(years: 0, months: 0, days: 0, totalDays: 0))
    }

    func testExactlyOneDay() {
        let breakdown = ElapsedTimeBreakdown.compute(
            from: utc(2025, 1, 1), to: utc(2025, 1, 2), calendar: utcCalendar
        )
        XCTAssertEqual(breakdown.years, 0)
        XCTAssertEqual(breakdown.months, 0)
        XCTAssertEqual(breakdown.days, 1)
        XCTAssertEqual(breakdown.totalDays, 1)
    }

    func testSevenDays() {
        let breakdown = ElapsedTimeBreakdown.compute(
            from: utc(2025, 6, 1), to: utc(2025, 6, 8), calendar: utcCalendar
        )
        XCTAssertEqual(breakdown.days, 7)
        XCTAssertEqual(breakdown.totalDays, 7)
    }

    func testFullNonLeapYearIs365Days() {
        let breakdown = ElapsedTimeBreakdown.compute(
            from: utc(2025, 1, 1), to: utc(2026, 1, 1), calendar: utcCalendar
        )
        XCTAssertEqual(breakdown.years, 1)
        XCTAssertEqual(breakdown.months, 0)
        XCTAssertEqual(breakdown.days, 0)
        XCTAssertEqual(breakdown.totalDays, 365)
    }

    func testFullLeapYearIs366Days() {
        // 2024 is a leap year (includes Feb 29), so a full year spans 366 days.
        let breakdown = ElapsedTimeBreakdown.compute(
            from: utc(2024, 1, 1), to: utc(2025, 1, 1), calendar: utcCalendar
        )
        XCTAssertEqual(breakdown.years, 1)
        XCTAssertEqual(breakdown.totalDays, 366)
    }

    func testCompoundYearsMonthsDays() {
        // 2023-01-10 → 2025-04-15 is exactly 2 years, 3 months, 5 days.
        let breakdown = ElapsedTimeBreakdown.compute(
            from: utc(2023, 1, 10), to: utc(2025, 4, 15), calendar: utcCalendar
        )
        XCTAssertEqual(breakdown.years, 2)
        XCTAssertEqual(breakdown.months, 3)
        XCTAssertEqual(breakdown.days, 5)
        XCTAssertGreaterThanOrEqual(breakdown.totalDays, 730)
    }

    // MARK: Leap-day starts (anniversary clamping)

    func testLeapDayStartToFeb28NextYearIsExactlyOneYear() {
        // Foundation clamps the missing Feb 29 anniversary: 2024-02-29 → 2025-02-28
        // reports exactly one year (not 0y 11m 30d), and 2025 is not a leap year so
        // the span is 365 whole days.
        let breakdown = ElapsedTimeBreakdown.compute(
            from: utc(2024, 2, 29), to: utc(2025, 2, 28), calendar: utcCalendar
        )
        XCTAssertEqual(breakdown, ElapsedTimeBreakdown(years: 1, months: 0, days: 0, totalDays: 365))
    }

    func testLeapDayStartToMarch1NextYearIsOneYearOneDay() {
        // One day past the clamped anniversary: 1 year 0 months 1 day, 366 days.
        let breakdown = ElapsedTimeBreakdown.compute(
            from: utc(2024, 2, 29), to: utc(2025, 3, 1), calendar: utcCalendar
        )
        XCTAssertEqual(breakdown, ElapsedTimeBreakdown(years: 1, months: 0, days: 1, totalDays: 366))
    }

    // MARK: End-of-month clamping

    func testJan31ToFeb28IsOneMonthZeroDays() {
        // Foundation clamps "one month after Jan 31" to Feb 28, so the pair reports
        // a whole month with no remainder days — this drives user-visible copy.
        let breakdown = ElapsedTimeBreakdown.compute(
            from: utc(2025, 1, 31), to: utc(2025, 2, 28), calendar: utcCalendar
        )
        XCTAssertEqual(breakdown, ElapsedTimeBreakdown(years: 0, months: 1, days: 0, totalDays: 28))
    }

    func testJan31ToMarch1IsOneMonthOneDay() {
        let breakdown = ElapsedTimeBreakdown.compute(
            from: utc(2025, 1, 31), to: utc(2025, 3, 1), calendar: utcCalendar
        )
        XCTAssertEqual(breakdown, ElapsedTimeBreakdown(years: 0, months: 1, days: 1, totalDays: 29))
    }

    func testJan31ToMarch31IsTwoMonthsZeroDays() {
        let breakdown = ElapsedTimeBreakdown.compute(
            from: utc(2025, 1, 31), to: utc(2025, 3, 31), calendar: utcCalendar
        )
        XCTAssertEqual(breakdown, ElapsedTimeBreakdown(years: 0, months: 2, days: 0, totalDays: 59))
    }

    // MARK: Symmetry / future starts

    func testFutureStartIsSwappedNotNegative() {
        let early = utc(2025, 1, 1)
        let late = utc(2025, 3, 20)
        let forward = ElapsedTimeBreakdown.compute(from: early, to: late, calendar: utcCalendar)
        let backward = ElapsedTimeBreakdown.compute(from: late, to: early, calendar: utcCalendar)
        XCTAssertEqual(forward, backward)
        XCTAssertGreaterThanOrEqual(backward.years, 0)
        XCTAssertGreaterThanOrEqual(backward.months, 0)
        XCTAssertGreaterThanOrEqual(backward.days, 0)
        XCTAssertGreaterThanOrEqual(backward.totalDays, 0)
    }

    // MARK: UTC whole-24h day boundary

    func testUTCDayCountsWhole24HourPeriodsNotMidnightCrossings() {
        // 23:30 → next day 00:30 is only one hour and crosses midnight, but it is
        // NOT a whole 24h period measured from the start's time-of-day → 0 days.
        let breakdown = ElapsedTimeBreakdown.compute(
            from: utc(2025, 1, 1, 23, 30), to: utc(2025, 1, 2, 0, 30), calendar: utcCalendar
        )
        XCTAssertEqual(breakdown.totalDays, 0)
        XCTAssertEqual(breakdown.days, 0)
    }

    func testUTCJustOverOneWhole24HourPeriodIsOneDay() {
        // 23:30 → +25h (next-next day 00:30) is one whole 24h period plus an hour.
        let breakdown = ElapsedTimeBreakdown.compute(
            from: utc(2025, 1, 1, 23, 30), to: utc(2025, 1, 3, 0, 30), calendar: utcCalendar
        )
        XCTAssertEqual(breakdown.totalDays, 1)
    }

    // MARK: DST day-boundary correctness

    func testDSTSpringForwardCountsTwoCalendarDays() {
        // US spring-forward: Sun Mar 9 2025 the local day is only 23 hours long.
        // From Mar 8 noon to Mar 10 noon only 47 real hours elapse, yet that is two
        // calendar days — a DST-aware calendar must report 2, not floor(47/24)=1.
        let start = newYork(2025, 3, 8, 12, 0)
        let end = newYork(2025, 3, 10, 12, 0)

        let dstAware = ElapsedTimeBreakdown.compute(from: start, to: end, calendar: newYorkCalendar)
        XCTAssertEqual(dstAware.totalDays, 2, "Calendar days must survive a spring-forward transition")
        XCTAssertEqual(dstAware.days, 2)

        // Same instants measured in the no-DST UTC calendar count whole 24h periods:
        // 47 real hours → floor(47/24) = 1. The contrast pins the DST behavior.
        let noDST = ElapsedTimeBreakdown.compute(from: start, to: end, calendar: utcCalendar)
        XCTAssertEqual(noDST.totalDays, 1)
    }

    func testDSTFallBackCountsTwoCalendarDays() {
        // US fall-back: Sun Nov 2 2025 the local day is 25 hours long; two calendar
        // days still report 2 even though ~49 real hours elapse.
        let start = newYork(2025, 11, 1, 12, 0)
        let end = newYork(2025, 11, 3, 12, 0)
        let breakdown = ElapsedTimeBreakdown.compute(from: start, to: end, calendar: newYorkCalendar)
        XCTAssertEqual(breakdown.totalDays, 2)
        XCTAssertEqual(breakdown.days, 2)
    }

    // MARK: utcCalendar properties

    func testUTCCalendarHasNoDaylightSaving() {
        // The invariant is a fixed zero offset with no DST — not the spelling of the
        // zone identifier (Foundation normalizes "UTC" to "GMT" on some platforms).
        let zone = ElapsedTimeBreakdown.utcCalendar.timeZone
        XCTAssertEqual(zone.secondsFromGMT(), 0)
        XCTAssertFalse(zone.isDaylightSavingTime(for: Date()))
        XCTAssertEqual(ElapsedTimeBreakdown.utcCalendar.identifier, .gregorian)
    }

    // MARK: Hashable contract (DK-9)

    func testHashableUsableInSet() {
        let value = ElapsedTimeBreakdown(years: 1, months: 2, days: 3, totalDays: 400)
        let equal = ElapsedTimeBreakdown(years: 1, months: 2, days: 3, totalDays: 400)
        let different = ElapsedTimeBreakdown(years: 0, months: 0, days: 0, totalDays: 0)
        let set: Set<ElapsedTimeBreakdown> = [value, equal, different]
        XCTAssertEqual(set.count, 2) // value == equal collapse to one entry
        XCTAssertTrue(set.contains(value))
        XCTAssertTrue(set.contains(different))
    }
}
