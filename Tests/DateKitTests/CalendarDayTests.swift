//
//  CalendarDayTests.swift
//  DateKitTests
//
// The typed calendar day: storage form, instant anchors, day math, and the UTC display rule.
// Locales are pinned and zones are injected, so every assertion is literal — no dependence on the
// host's locale or process-global time zone. Epoch literals are UTC wall-clock moments computed by
// hand and pinned, so a regression in the anchors cannot hide behind the same code computing the
// expectation.
//
// Moved with the type from CommittedKit (2026-08-03), minus the SobrietyStart convergence test,
// which asserts a CommittedKit domain rule and stays beside it.

import Testing
import Foundation
import DateKit

@Suite("CalendarDay")
struct CalendarDayTests {
    private let enUS = Locale(identifier: "en_US")
    private let esES = Locale(identifier: "es_ES")

    // MARK: - Storage form

    @Test("storageString zero-pads to strict yyyy-MM-dd")
    func storageStringZeroPads() {
        #expect(CalendarDay(year: 2026, month: 5, day: 2).storageString == "2026-05-02")
        #expect(CalendarDay(year: 2026, month: 12, day: 31).storageString == "2026-12-31")
        #expect(CalendarDay(year: 999, month: 1, day: 1).storageString == "0999-01-01")
    }

    @Test("storageString round-trips through init?(storageString:) identically")
    func storageStringRoundTrips() {
        let days = [
            CalendarDay(year: 2026, month: 5, day: 2),
            CalendarDay(year: 2024, month: 2, day: 29),
            CalendarDay(year: 1999, month: 12, day: 31),
            CalendarDay(year: 2026, month: 1, day: 1)
        ]
        for day in days {
            #expect(CalendarDay(storageString: day.storageString) == day)
        }
    }

    @Test("Malformed storage strings are rejected", arguments: [
        "2026-5-2",             // unpadded fields
        "2026/05/02",           // wrong separators
        "2026-05-02T00:00Z",    // trailing time — not the storage form
        "",                     // empty
        "2026-05-2",            // one unpadded field
        "26-05-02",             // two-digit year
        "2026-05-02 ",          // trailing space (11 chars)
        " 2026-05-02",          // leading space
        "yyyy-MM-dd",           // non-digits in digit positions
        "2026-05-0x",           // non-digit tail
        "2026+05-02",           // wrong separator at position 4
        "²026-05-02"            // non-ASCII digit (multi-byte, count != 10 in UTF-8)
    ])
    func malformedStorageStringsAreRejected(malformed: String) {
        #expect(CalendarDay(storageString: malformed) == nil)
    }

    @Test("Out-of-range fields PARSE — validation is format-strict, range-agnostic")
    func outOfRangeFieldsParse() {
        // Pinned deliberately: the type trusts its fields everywhere (init(year:month:day:)
        // accepts the same values), so the parser checks SHAPE only. A range check here would be
        // a second, divergent authority on validity.
        let parsed = CalendarDay(storageString: "2026-13-40")
        #expect(parsed == CalendarDay(year: 2026, month: 13, day: 40))
    }

    // MARK: - init(containing:in:) — the local-pick reader

    @Test("An LA evening instant is one day in LA and the NEXT day in UTC (the misread, now explicit)")
    func losAngelesEveningVersusUTC() {
        // 2026-05-02 18:30 in LA == 2026-05-03 01:30 UTC. The old instant-typed reads picked one
        // of these silently per call site; the calendar parameter makes the choice visible.
        let laEvening = utcInstant(2026, 5, 3, 1, 30, 0)
        #expect(CalendarDay(containing: laEvening, in: gregorianCalendar(zoneIdentifier: "America/Los_Angeles"))
            == CalendarDay(year: 2026, month: 5, day: 2))
        #expect(CalendarDay(containing: laEvening, in: ElapsedTimeBreakdown.utcCalendar)
            == CalendarDay(year: 2026, month: 5, day: 3))
    }

    @Test("Auckland morning: Jan 3 08:00 NZDT reads as Jan 3 there and Jan 2 in UTC")
    func aucklandMorning() {
        // Auckland observes NZDT (UTC+13) in January.
        let aucklandMorning = utcInstant(2026, 1, 2, 19, 0, 0)
        #expect(CalendarDay(containing: aucklandMorning, in: gregorianCalendar(zoneIdentifier: "Pacific/Auckland"))
            == CalendarDay(year: 2026, month: 1, day: 3))
        #expect(CalendarDay(containing: aucklandMorning, in: ElapsedTimeBreakdown.utcCalendar)
            == CalendarDay(year: 2026, month: 1, day: 2))
    }

    @Test("Kiritimati (UTC+14, the earliest zone) crosses to the next day by 10:00 UTC")
    func kiritimatiReadsNextDay() {
        let instant = utcInstant(2026, 1, 2, 11, 0, 0) // 01:00 on Jan 3 in Kiritimati
        #expect(CalendarDay(containing: instant, in: gregorianCalendar(zoneIdentifier: "Pacific/Kiritimati"))
            == CalendarDay(year: 2026, month: 1, day: 3))
    }

    @Test("Chatham (+13:45 in January DST) honors the 45-minute offset at the day boundary")
    func chathamFractionalOffset() {
        let chatham = gregorianCalendar(zoneIdentifier: "Pacific/Chatham")
        // 10:30 UTC + 13:45 = 00:15 on Jan 3; 10:00 UTC + 13:45 = 23:45, still Jan 2.
        #expect(CalendarDay(containing: utcInstant(2026, 1, 2, 10, 30, 0), in: chatham)
            == CalendarDay(year: 2026, month: 1, day: 3))
        #expect(CalendarDay(containing: utcInstant(2026, 1, 2, 10, 0, 0), in: chatham)
            == CalendarDay(year: 2026, month: 1, day: 2))
    }

    // MARK: - Instant anchors

    @Test("startOfDayUTC and noonUTC are the exact expected instants")
    func anchorsAreExactInstants() {
        // 2026-01-02: 20,455 days after the epoch (56 years x 365 + 14 leap days + 1).
        let day = CalendarDay(year: 2026, month: 1, day: 2)
        #expect(day.startOfDayUTC == Date(timeIntervalSince1970: 1_767_312_000))
        #expect(day.noonUTC == Date(timeIntervalSince1970: 1_767_355_200))
    }

    @Test("Both anchors round-trip through init(containing:in: UTC)")
    func anchorsRoundTrip() {
        let days = [
            CalendarDay(year: 2026, month: 1, day: 2),
            CalendarDay(year: 2024, month: 2, day: 29),
            CalendarDay(year: 1970, month: 1, day: 1)
        ]
        for day in days {
            #expect(CalendarDay(containing: day.startOfDayUTC, in: ElapsedTimeBreakdown.utcCalendar) == day)
            #expect(CalendarDay(containing: day.noonUTC, in: ElapsedTimeBreakdown.utcCalendar) == day)
        }
    }

    // MARK: - instant(hour:minute:in:)

    @Test("9am resolves to the exact local wall-clock instant in LA and Auckland")
    func nineAMIsExactPerZone() {
        let day = CalendarDay(year: 2026, month: 1, day: 2)
        // LA is PST (UTC-8) in January: 09:00 local == 17:00 UTC.
        #expect(day.instant(hour: 9, in: gregorianCalendar(zoneIdentifier: "America/Los_Angeles"))
            == Date(timeIntervalSince1970: 1_767_373_200))
        // Auckland is NZDT (UTC+13) in January: 09:00 local == 20:00 UTC the previous day.
        #expect(day.instant(hour: 9, in: gregorianCalendar(zoneIdentifier: "Pacific/Auckland"))
            == Date(timeIntervalSince1970: 1_767_297_600))
    }

    @Test("Spring-forward day: 9am is the exact wall-clock instant, and a skipped time resolves sanely")
    func springForwardResolvesSanely() throws {
        // US DST starts 2026-03-08 (02:00 -> 03:00 in LA).
        let springForwardDay = CalendarDay(year: 2026, month: 3, day: 8)
        let losAngeles = gregorianCalendar(zoneIdentifier: "America/Los_Angeles")

        // 09:00 PDT (UTC-7, after the jump) == 16:00 UTC — wall-clock exact, not midnight+9h.
        #expect(springForwardDay.instant(hour: 9, in: losAngeles)
            == Date(timeIntervalSince1970: 1_772_985_600))

        // 02:30 does not exist that day; the calendar resolves past the gap, on the SAME day,
        // into the 3 o'clock hour.
        let skippedWallTime = springForwardDay.instant(hour: 2, minute: 30, in: losAngeles)
        let resolved = try #require(skippedWallTime)
        #expect(CalendarDay(containing: resolved, in: losAngeles) == springForwardDay)
        #expect(losAngeles.component(.hour, from: resolved) == 3)
    }

    // MARK: - days(since:)

    @Test("Adjacent days: signed, zero on identity")
    func adjacentDays() {
        let january1 = CalendarDay(year: 2026, month: 1, day: 1)
        let january2 = CalendarDay(year: 2026, month: 1, day: 2)
        #expect(january2.days(since: january1) == 1)
        #expect(january1.days(since: january2) == -1)
        #expect(january1.days(since: january1) == 0)
    }

    @Test("Across a DST transition the count is exact — UTC math never sees the 23-hour local day")
    func acrossDSTTransition() {
        // 2026-03-08 is the US spring-forward day; local-midnight subtraction in LA would span a
        // 23-hour day. days(since:) is UTC start-of-day math, so the hazard cannot exist.
        let beforeTransition = CalendarDay(year: 2026, month: 3, day: 7)
        let afterTransition = CalendarDay(year: 2026, month: 3, day: 9)
        #expect(afterTransition.days(since: beforeTransition) == 2)
    }

    @Test("Across Feb 29")
    func acrossLeapDay() {
        let leapFebruary28 = CalendarDay(year: 2024, month: 2, day: 28)
        let leapMarch1 = CalendarDay(year: 2024, month: 3, day: 1)
        #expect(leapMarch1.days(since: leapFebruary28) == 2)

        let commonYearSpanStart = CalendarDay(year: 2023, month: 3, day: 1)
        #expect(leapMarch1.days(since: commonYearSpanStart) == 366) // spans Feb 29 2024
        #expect(commonYearSpanStart.days(since: CalendarDay(year: 2022, month: 3, day: 1)) == 365)
    }

    // MARK: - Comparable

    @Test("Lexicographic ordering across day, month, and year boundaries")
    func comparableOrdering() {
        #expect(CalendarDay(year: 2026, month: 5, day: 2) < CalendarDay(year: 2026, month: 5, day: 3))
        #expect(CalendarDay(year: 2026, month: 1, day: 31) < CalendarDay(year: 2026, month: 2, day: 1))
        #expect(CalendarDay(year: 2025, month: 12, day: 31) < CalendarDay(year: 2026, month: 1, day: 1))
        #expect(!(CalendarDay(year: 2026, month: 1, day: 1) < CalendarDay(year: 2026, month: 1, day: 1)))

        let unsorted = [
            CalendarDay(year: 2026, month: 1, day: 1),
            CalendarDay(year: 2025, month: 12, day: 31),
            CalendarDay(year: 2026, month: 2, day: 1),
            CalendarDay(year: 2026, month: 1, day: 15)
        ]
        #expect(unsorted.sorted().map(\.storageString)
            == ["2025-12-31", "2026-01-01", "2026-01-15", "2026-02-01"])
    }

    // MARK: - Codable

    @Test("Encodes as the single canonical storage string and round-trips")
    func codableRoundTrip() throws {
        let day = CalendarDay(year: 2026, month: 5, day: 2)
        let encoded = try JSONEncoder().encode([day])
        #expect(String(data: encoded, encoding: .utf8) == "[\"2026-05-02\"]")

        let decoded = try JSONDecoder().decode([CalendarDay].self, from: encoded)
        #expect(decoded == [day])
    }

    @Test("Decode fails on garbage rather than producing a silently-wrong day", arguments: [
        "[\"2026/05/02\"]",
        "[\"not-a-day!!\"]",
        "[\"2026-5-2\"]",
        "[42]"
    ])
    func codableDecodeFailsOnGarbage(json: String) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([CalendarDay].self, from: Data(json.utf8))
        }
    }

    // MARK: - displayString

    @Test("Renders the day's own date in en_US at every style — a UTC read, never the host zone")
    func displayStringEnglishExactStrings() {
        // 2026-01-02 is a Friday. A device-zone read of the midnight-UTC anchor would render
        // Jan 1 everywhere west of UTC; the UTC formatter names THIS day on any host. The calendar
        // is injected (Gregorian, far-west zone) rather than left ambient, so the literal strings
        // hold whatever calendar SYSTEM the host is set to — the parameter's whole purpose.
        let day = CalendarDay(year: 2026, month: 1, day: 2)
        let losAngeles = gregorianCalendar(zoneIdentifier: "America/Los_Angeles")
        #expect(day.displayString(style: .short, locale: enUS, calendar: losAngeles) == "1/2/2026")
        #expect(day.displayString(style: .medium, locale: enUS, calendar: losAngeles) == "Jan 2, 2026")
        #expect(day.displayString(style: .long, locale: enUS, calendar: losAngeles) == "Friday, January 2, 2026")
    }

    @Test("Renders the day's own date in es_ES")
    func displayStringSpanishNamesTheDay() {
        // Asserted on the day-naming fragment, not the full string — weekday/comma shapes vary by
        // CLDR release, the "2 de enero de 2026" core does not.
        let day = CalendarDay(year: 2026, month: 1, day: 2)
        let madrid = gregorianCalendar(zoneIdentifier: "Europe/Madrid")
        #expect(day.displayString(style: .long, locale: esES, calendar: madrid)
            .contains("2 de enero de 2026"))
    }

    @Test("The user's calendar SYSTEM survives; only its zone is overridden")
    func displayStringKeepsTheCalendarSystemAndOverridesTheZone() {
        // Only the ZONE is a storage detail here (a day anchor read in the device zone names the
        // neighbouring day). The calendar system is the user's: hard-coding the Gregorian
        // `utcCalendar` rendered "2026" for a Buddhist-calendar user, on the same screen as a
        // track-time start that correctly said "2569".
        let day = CalendarDay(year: 2026, month: 1, day: 2)
        var buddhist = Calendar(identifier: .buddhist)
        // A far-east zone, deliberately: if the zone were honoured, the midnight-UTC anchor would
        // name Jan 2 13:00 — still Jan 2 — so pair it with the far-WEST case below, where honouring
        // the zone would name Jan 1.
        buddhist.timeZone = TimeZone(identifier: "Pacific/Auckland")!
        // 2026 CE is 2569 BE. Locale pinned to en_US so this asserts the era arithmetic, not a
        // locale's numbering system.
        let rendered = day.displayString(style: .medium, locale: enUS, calendar: buddhist)
        #expect(rendered.contains("2569"))
        #expect(rendered.contains("Jan 2"))

        // Zone override, far west: a midnight-UTC anchor read in Los Angeles is the PREVIOUS
        // evening, so a leaked device zone would render Jan 1 here.
        var gregorianLosAngeles = Calendar(identifier: .gregorian)
        gregorianLosAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        #expect(day.displayString(style: .medium, locale: enUS, calendar: gregorianLosAngeles)
            == "Jan 2, 2026")
    }

    @Test("A day minted from an LA evening pick displays as the picked day (the shipped bug class, end to end)")
    func displayStringEndToEndFromLocalPick() {
        // The pick: 18:30 on May 2 in LA (stored-legacy shape: 01:30 May 3 UTC). Read in the
        // picker's own calendar, the day is May 2 — and the display names May 2 in every zone.
        let pickInstant = utcInstant(2026, 5, 3, 1, 30, 0)
        let losAngeles = gregorianCalendar(zoneIdentifier: "America/Los_Angeles")
        let pickedDay = CalendarDay(containing: pickInstant, in: losAngeles)
        #expect(pickedDay.displayString(style: .medium, locale: enUS, calendar: losAngeles) == "May 2, 2026")
    }

    // MARK: - Fixtures

    /// An absolute instant built from its UTC wall-clock components, so the tests read as UTC moments.
    private func utcInstant(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day
        components.hour = hour; components.minute = minute; components.second = second
        return ElapsedTimeBreakdown.utcCalendar.date(from: components)!
    }

    /// A Gregorian calendar pinned to a fixed IANA zone — the injectable stand-in for the ambient
    /// `.autoupdatingCurrent`, with no dependence on the host's process-global time zone.
    private func gregorianCalendar(zoneIdentifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zoneIdentifier)!
        return calendar
    }
}
