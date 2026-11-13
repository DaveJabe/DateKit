//
//  CalendarMonthTests.swift
//  DateKitTests
//
// The month type, the integer day arithmetic under it, and the month grid. The arithmetic is checked
// against Foundation's own Gregorian calendar for every day from 1583 to 2600, and the grid for every
// month in that span with each of the seven first weekdays, so the grid a calendar draws is right by
// exhaustion, not by a handful of examples.

import Foundation
import Testing
import DateKit

@Suite("CalendarMonth")
struct CalendarMonthTests {
    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    // MARK: - Month

    @Test("an out-of-range month carries into the year")
    func monthNormalization() {
        #expect(CalendarMonth(year: 2026, month: 13) == CalendarMonth(year: 2027, month: 1))
        #expect(CalendarMonth(year: 2026, month: 0) == CalendarMonth(year: 2025, month: 12))
        #expect(CalendarMonth(year: 2026, month: -11) == CalendarMonth(year: 2025, month: 1))
        #expect(CalendarMonth(year: 2026, month: -12) == CalendarMonth(year: 2024, month: 12))
        #expect(CalendarMonth(year: 2026, month: 25) == CalendarMonth(year: 2028, month: 1))
        #expect(CalendarMonth(year: 2026, month: 1).adding(months: -1) == CalendarMonth(year: 2025, month: 12))
        #expect(CalendarMonth(year: 2026, month: 12).adding(months: 1) == CalendarMonth(year: 2027, month: 1))
        #expect(CalendarMonth(year: 2026, month: 5).adding(years: -4) == CalendarMonth(year: 2022, month: 5))
    }

    @Test("month lengths follow the Gregorian leap rule")
    func monthLengths() {
        #expect(CalendarMonth(year: 1900, month: 2).numberOfDays == 28)
        #expect(CalendarMonth(year: 2000, month: 2).numberOfDays == 29)
        #expect(CalendarMonth(year: 2024, month: 2).numberOfDays == 29)
        #expect(CalendarMonth(year: 2026, month: 2).numberOfDays == 28)
        #expect(CalendarMonth(year: 2100, month: 2).numberOfDays == 28)
        #expect(CalendarMonth(year: 2026, month: 4).numberOfDays == 30)
        #expect(CalendarMonth(year: 2026, month: 12).numberOfDays == 31)
        #expect(CalendarMonth(year: 2024, month: 2).lastDay == CalendarDay(year: 2024, month: 2, day: 29))
    }

    @Test("isValid rejects days the calendar doesn't have")
    func validity() {
        #expect(CalendarDay(year: 2024, month: 2, day: 29).isValid)
        #expect(!CalendarDay(year: 2023, month: 2, day: 29).isValid)
        #expect(!CalendarDay(year: 2026, month: 2, day: 30).isValid)
        #expect(!CalendarDay(year: 2026, month: 13, day: 1).isValid)
        #expect(!CalendarDay(year: 2026, month: 5, day: 0).isValid)
        #expect(!CalendarDay(year: 2026, month: 0, day: 1).isValid)
    }

    // MARK: - Day arithmetic

    @Test("day stepping and weekdays match Foundation for every day from 1583 to 2600")
    func arithmeticMatchesFoundation() throws {
        let calendar = Self.utcCalendar
        var instant = try #require(calendar.date(from: DateComponents(year: 1583, month: 1, day: 1, hour: 12)))
        let end = try #require(calendar.date(from: DateComponents(year: 2600, month: 12, day: 31, hour: 12)))
        var day = CalendarDay(year: 1583, month: 1, day: 1)
        var mismatches = 0
        while instant <= end {
            let expected = CalendarDay(containing: instant, in: calendar)
            if day != expected || day.weekday != calendar.component(.weekday, from: instant) || !day.isValid {
                mismatches += 1
            }
            day = day.adding(days: 1)
            instant = try #require(calendar.date(byAdding: .day, value: 1, to: instant))
        }
        #expect(mismatches == 0)
    }

    @Test("large day offsets round-trip and agree with days(since:)")
    func largeOffsets() {
        let day = CalendarDay(year: 2026, month: 11, day: 13)
        #expect(day.adding(days: 100_000).adding(days: -100_000) == day)
        #expect(day.adding(days: 365) == CalendarDay(year: 2027, month: 11, day: 13))
        #expect(day.adding(days: -366) == CalendarDay(year: 2025, month: 11, day: 12))
        #expect(CalendarDay(year: 2024, month: 2, day: 28).adding(days: 1) == CalendarDay(year: 2024, month: 2, day: 29))
        #expect(CalendarDay(year: 2023, month: 2, day: 28).adding(days: 1) == CalendarDay(year: 2023, month: 3, day: 1))
        #expect(day.adding(days: 12_345).days(since: day) == 12_345)
        #expect(CalendarDay(year: 2026, month: 11, day: 13).weekday == 6) // a Friday
    }

    // MARK: - Grid

    @Test("May 2027 starts its grid on the Sunday or Monday before the 1st")
    func knownGrid() {
        let may2027 = CalendarMonth(year: 2027, month: 5)
        let sundayFirst = CalendarMonthGrid(month: may2027, firstWeekday: 1)
        #expect(sundayFirst.days.first == CalendarDay(year: 2027, month: 4, day: 25))
        #expect(sundayFirst.days.last == CalendarDay(year: 2027, month: 6, day: 5))
        let mondayFirst = CalendarMonthGrid(month: may2027, firstWeekday: 2)
        #expect(mondayFirst.days.first == CalendarDay(year: 2027, month: 4, day: 26))
        #expect(mondayFirst.weekdayColumns == [2, 3, 4, 5, 6, 7, 1])
    }

    @Test("a first weekday outside 1...7 wraps into range")
    func firstWeekdayNormalization() {
        let month = CalendarMonth(year: 2026, month: 11)
        #expect(CalendarMonthGrid(month: month, firstWeekday: 0).firstWeekday == 7)
        #expect(CalendarMonthGrid(month: month, firstWeekday: 8).firstWeekday == 1)
        #expect(CalendarMonthGrid(month: month, firstWeekday: -6).firstWeekday == 1)
    }

    @Test("every grid from 1583 to 2600 holds six whole weeks around its month", arguments: 1 ... 7)
    func everyGrid(firstWeekday: Int) {
        var failures: [String] = []
        for year in 1583 ... 2600 {
            for monthNumber in 1 ... 12 {
                let month = CalendarMonth(year: year, month: monthNumber)
                let grid = CalendarMonthGrid(month: month, firstWeekday: firstWeekday)
                let days = grid.days
                guard days.count == 42, grid.weeks.count == 6, grid.weeks.allSatisfy({ $0.count == 7 }) else {
                    failures.append("\(year)-\(monthNumber): shape")
                    continue
                }
                let firstOfMonth = days.firstIndex(of: month.firstDay) ?? -1
                let monthDays = days.filter { month.contains($0) }
                if days[0].weekday != firstWeekday
                    || !(0 ..< 7).contains(firstOfMonth)
                    || monthDays.count != month.numberOfDays
                    || monthDays.last != month.lastDay
                    || zip(days, days.dropFirst()).contains(where: { $0.adding(days: 1) != $1 })
                    || days.enumerated().contains(where: { $1.weekday != grid.weekdayColumns[$0 % 7] }) {
                    failures.append("\(year)-\(monthNumber)")
                }
            }
        }
        #expect(failures.isEmpty, "\(failures.prefix(5))")
    }

    // MARK: - Names

    @Test("month titles follow the locale")
    func monthTitles() {
        let gregorian = Calendar(identifier: .gregorian)
        let may2027 = CalendarMonth(year: 2027, month: 5)
        #expect(may2027.displayName(locale: Locale(identifier: "en_US"), calendar: gregorian) == "May 2027")
        #expect(may2027.displayName(locale: Locale(identifier: "es_ES"), calendar: gregorian) == "mayo de 2027")
        #expect(may2027.monthName(locale: Locale(identifier: "es_ES"), calendar: gregorian, abbreviated: false) == "mayo")
        #expect(may2027.yearName(locale: Locale(identifier: "en_US"), calendar: gregorian) == "2027")
    }

    @Test("a Gregorian-aligned calendar names the year its own way")
    func alignedCalendarYears() {
        let may2027 = CalendarMonth(year: 2027, month: 5)
        let enUS = Locale(identifier: "en_US")
        #expect(may2027.yearName(locale: enUS, calendar: Calendar(identifier: .buddhist)).contains("2570"))
        #expect(may2027.yearName(locale: enUS, calendar: Calendar(identifier: .japanese)).contains("Reiwa"))
        #expect(may2027.displayName(locale: enUS, calendar: Calendar(identifier: .buddhist)).contains("May"))
    }

    @Test("a calendar with other months falls back to Gregorian names", arguments: [
        Calendar.Identifier.hebrew, .islamicUmmAlQura, .persian, .chinese, .coptic, .ethiopicAmeteMihret, .indian
    ])
    func unalignedCalendarFallsBack(identifier: Calendar.Identifier) {
        let may2027 = CalendarMonth(year: 2027, month: 5)
        let enUS = Locale(identifier: "en_US")
        #expect(may2027.displayName(locale: enUS, calendar: Calendar(identifier: identifier)) == "May 2027")
        #expect(may2027.monthName(locale: enUS, calendar: Calendar(identifier: identifier), abbreviated: true) == "May")
    }
}
