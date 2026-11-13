//
//  CalendarDayPickingTests.swift
//  DateKitTests
//
// Where a CalendarDay picker meets the Date it edits. The sweep runs every day from 1970 to 2040 in
// the zones where days misbehave: days that start at 01:00 because the clocks spring forward at
// midnight (Santiago, Havana, the Azores, São Paulo, Tehran, Cairo, Beirut), half-hour shifts
// (Lord Howe), odd offsets (Chatham, Kathmandu, St. John's), and the five zones that skipped a whole
// day crossing the date line. Every pickable day must read back as itself, and the skipped days must
// be exactly the ones the zone data skips.

import Foundation
import Testing
import DateKit

@Suite("CalendarDayPicking")
struct CalendarDayPickingTests {
    /// Each zone with the days its data skips between 1970 and 2040 (crossings of the date line).
    static let sweptZones: [(identifier: String, skippedDays: Set<CalendarDay>)] = [
        ("UTC", []),
        ("America/Santiago", []),
        ("America/Havana", []),
        ("Atlantic/Azores", []),
        ("America/Sao_Paulo", []),
        ("Asia/Tehran", []),
        ("Africa/Cairo", []),
        ("Asia/Beirut", []),
        ("Australia/Lord_Howe", []),
        ("Pacific/Chatham", []),
        ("Asia/Kathmandu", []),
        ("America/St_Johns", []),
        ("Europe/Madrid", []),
        ("America/Mexico_City", []),
        ("Pacific/Apia", [CalendarDay(year: 2011, month: 12, day: 30)]),
        ("Pacific/Fakaofo", [CalendarDay(year: 2011, month: 12, day: 30)]),
        ("Pacific/Kiritimati", [CalendarDay(year: 1994, month: 12, day: 31)]),
        ("Pacific/Kanton", [CalendarDay(year: 1994, month: 12, day: 31)]),
        ("Pacific/Kwajalein", [CalendarDay(year: 1993, month: 8, day: 21)])
    ]

    private static func zone(_ identifier: String) -> TimeZone {
        TimeZone(identifier: identifier)!
    }

    private static func instant(_ day: CalendarDay, hour: Int, minute: Int = 0, in zone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return day.instant(hour: hour, minute: minute, in: calendar)!
    }

    // MARK: - The sweep

    @Test("every day from 1970 to 2040 picks as itself", arguments: CalendarDayPickingTests.sweptZones.map(\.identifier))
    func sweep(zoneIdentifier: String) throws {
        let zone = Self.zone(zoneIdentifier)
        let picking = CalendarDayPicking(timeZone: zone)
        let expectedSkips = try #require(Self.sweptZones.first { $0.identifier == zoneIdentifier }).skippedDays
        // Times of day that a midnight-skipping day lacks (00:30), that a spring-forward gap often
        // lacks (02:30), and the edges of the day.
        let reference = CalendarDay(year: 2026, month: 6, day: 15)
        let times = [(0, 0), (0, 30), (2, 30), (12, 0), (23, 59)].map { Self.instant(reference, hour: $0.0, minute: $0.1, in: zone) }

        var skipped: Set<CalendarDay> = []
        var misreads: [String] = []
        var lostNoons: [String] = []
        var day = CalendarDay(year: 1970, month: 1, day: 1)
        let last = CalendarDay(year: 2040, month: 12, day: 31)
        while day <= last {
            if picking.canPick(day) {
                for time in times {
                    guard let picked = picking.instant(picking: day, keepingTimeOf: time), picking.day(of: picked) == day else {
                        misreads.append(day.storageString)
                        break
                    }
                }
                // Noon exists on every day, so a noon pick keeps its time exactly.
                if let noonPick = picking.instant(picking: day, keepingTimeOf: times[3]),
                   picking.calendar.dateComponents([.hour, .minute], from: noonPick) != DateComponents(hour: 12, minute: 0) {
                    lostNoons.append(day.storageString)
                }
            } else {
                skipped.insert(day)
                #expect(picking.instant(picking: day, keepingTimeOf: times[3]) == nil)
            }
            day = day.adding(days: 1)
        }
        #expect(misreads.isEmpty, "\(misreads.prefix(5))")
        #expect(lostNoons.isEmpty, "\(lostNoons.prefix(5))")
        #expect(skipped == expectedSkips)
    }

    @Test("a time the day skipped resolves later on the same day")
    func springForwardGap() throws {
        // Santiago sprang forward at midnight on 11 September 2022: the day began at 01:00.
        let zone = Self.zone("America/Santiago")
        let picking = CalendarDayPicking(timeZone: zone)
        let day = CalendarDay(year: 2022, month: 9, day: 11)
        let halfPastMidnight = Self.instant(CalendarDay(year: 2026, month: 6, day: 15), hour: 0, minute: 30, in: zone)
        let picked = try #require(picking.instant(picking: day, keepingTimeOf: halfPastMidnight))
        #expect(picking.day(of: picked) == day)
        #expect(picking.calendar.dateComponents([.hour, .minute], from: picked) == DateComponents(hour: 1, minute: 30))
    }

    @Test("a pick keeps the edited date's time of day, seconds included")
    func keepsTimeOfDay() throws {
        let zone = Self.zone("Europe/Madrid")
        let picking = CalendarDayPicking(timeZone: zone)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let current = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 13, hour: 21, minute: 7, second: 42)))
        let picked = try #require(picking.instant(picking: CalendarDay(year: 2022, month: 3, day: 27), keepingTimeOf: current))
        #expect(calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: picked)
            == DateComponents(year: 2022, month: 3, day: 27, hour: 21, minute: 7, second: 42))
    }

    @Test("an invalid day can't be picked")
    func invalidDay() {
        let picking = CalendarDayPicking(timeZone: Self.zone("UTC"))
        #expect(!picking.canPick(CalendarDay(year: 2026, month: 2, day: 30)))
        #expect(!picking.canPick(CalendarDay(year: 2026, month: 13, day: 1)))
    }

    // MARK: - Bounds

    @Test("a maximum allows its whole day and clamps a later time on it")
    func maximumBound() throws {
        let zone = Self.zone("Europe/Madrid")
        let maximum = Self.instant(CalendarDay(year: 2026, month: 11, day: 13), hour: 15, in: zone)
        let picking = CalendarDayPicking(timeZone: zone, maximum: maximum)
        let lastDay = CalendarDay(year: 2026, month: 11, day: 13)
        #expect(picking.lastDay == lastDay)
        #expect(picking.canPick(lastDay))
        #expect(!picking.canPick(lastDay.adding(days: 1)))

        let evening = Self.instant(CalendarDay(year: 2026, month: 1, day: 2), hour: 20, in: zone)
        #expect(picking.instant(picking: lastDay, keepingTimeOf: evening) == maximum)
        let morning = Self.instant(CalendarDay(year: 2026, month: 1, day: 2), hour: 9, in: zone)
        #expect(picking.instant(picking: lastDay, keepingTimeOf: morning) == Self.instant(lastDay, hour: 9, in: zone))

        #expect(picking.allows(CalendarMonth(year: 2026, month: 11)))
        #expect(!picking.allows(CalendarMonth(year: 2026, month: 12)))
        #expect(picking.allows(years: 2015 ... 2026))
        #expect(!picking.allows(years: 2027 ... 2038))
    }

    @Test("a minimum allows its whole day and clamps an earlier time on it")
    func minimumBound() throws {
        let zone = Self.zone("America/Mexico_City")
        let minimum = Self.instant(CalendarDay(year: 2020, month: 3, day: 1), hour: 10, in: zone)
        let picking = CalendarDayPicking(timeZone: zone, minimum: minimum)
        let firstDay = CalendarDay(year: 2020, month: 3, day: 1)
        #expect(picking.firstDay == firstDay)
        #expect(picking.canPick(firstDay))
        #expect(!picking.canPick(firstDay.adding(days: -1)))
        let earlyMorning = Self.instant(CalendarDay(year: 2026, month: 1, day: 2), hour: 6, in: zone)
        #expect(picking.instant(picking: firstDay, keepingTimeOf: earlyMorning) == minimum)
        #expect(!picking.allows(CalendarMonth(year: 2020, month: 2)))
        #expect(picking.allows(CalendarMonth(year: 2020, month: 3)))
        #expect(!picking.allows(years: 2008 ... 2019))
    }

    @Test("without bounds, picks stay inside the supported years")
    func supportedYears() {
        let picking = CalendarDayPicking(timeZone: Self.zone("UTC"))
        #expect(picking.firstDay == CalendarDay(year: 1583, month: 1, day: 1))
        #expect(picking.lastDay == CalendarDay(year: 9999, month: 12, day: 31))
        #expect(!picking.canPick(CalendarDay(year: 1582, month: 12, day: 31)))
        #expect(!picking.allows(years: 1571 ... 1582))
        #expect(picking.allows(years: 1580 ... 1591))

        let veryEarly = Date(timeIntervalSince1970: -20_000_000_000) // 1336
        #expect(CalendarDayPicking(timeZone: Self.zone("UTC"), minimum: veryEarly).firstDay == picking.firstDay)
    }
}
