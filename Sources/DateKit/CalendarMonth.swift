//
//  CalendarMonth.swift
//  DateKit
//
//  A Gregorian month, and the integer day arithmetic a month calendar needs (weekday, day offsets),
//  all on `CalendarDay` with no `Calendar`, no time zone and no instant. A month view built on these
//  cannot be thrown off by a zone whose day starts at 01:00 or skips a date: no zone is consulted.
//  The one place a picked day meets a `Date` is `CalendarDayPicking`.
//

import Foundation

/// A month of the Gregorian calendar: year and month, no day.
///
/// Gregorian by convention, like `CalendarDay`, and proleptic: the Gregorian leap rule runs back past
/// 15 October 1582, where Foundation's Gregorian calendar switches to Julian. The domain is
/// contemporary dates (`CalendarDayPicking.supportedYears`).
public struct CalendarMonth: Hashable, Comparable, Sendable {
    public let year: Int
    /// 1...12.
    public let month: Int

    /// Carries an out-of-range month into the year: month 13 of 2026 is January 2027, month 0 is
    /// December 2025. Months are counted, so this needs no calendar.
    public init(year: Int, month: Int) {
        let zeroBasedMonth = month - 1
        let yearCarry = zeroBasedMonth >= 0 ? zeroBasedMonth / 12 : (zeroBasedMonth - 11) / 12
        self.year = year + yearCarry
        self.month = zeroBasedMonth - yearCarry * 12 + 1
    }

    /// The month `day` falls in.
    public init(containing day: CalendarDay) {
        self.init(year: day.year, month: day.month)
    }

    public static func < (lhs: CalendarMonth, rhs: CalendarMonth) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }
}

public extension CalendarMonth {
    func adding(months: Int) -> CalendarMonth {
        CalendarMonth(year: year, month: month + months)
    }

    func adding(years: Int) -> CalendarMonth {
        CalendarMonth(year: year + years, month: month)
    }

    var firstDay: CalendarDay {
        CalendarDay(year: year, month: month, day: 1)
    }

    var lastDay: CalendarDay {
        CalendarDay(year: year, month: month, day: numberOfDays)
    }

    var numberOfDays: Int {
        switch month {
        case 2: Self.isLeapYear(year) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    func contains(_ day: CalendarDay) -> Bool {
        day.year == year && day.month == month
    }

    /// The Gregorian rule: every fourth year, except centuries, except every fourth century.
    static func isLeapYear(_ year: Int) -> Bool {
        year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
    }
}

// MARK: - Day arithmetic

public extension CalendarDay {
    /// Whether the fields name a real Gregorian day (no Feb 30, no month 13).
    var isValid: Bool {
        guard (1 ... 12).contains(month) else { return false }
        return day >= 1 && day <= CalendarMonth(year: year, month: month).numberOfDays
    }

    /// The day `days` later, or earlier when negative, by counting days.
    func adding(days: Int) -> CalendarDay {
        CalendarDay(daysSinceEpoch: daysSinceEpoch + days)
    }

    /// 1 = Sunday … 7 = Saturday: the numbering of `Calendar.component(.weekday, from:)`.
    var weekday: Int {
        // 1970-01-01 was a Thursday (weekday 5).
        ((daysSinceEpoch + 4) % 7 + 7) % 7 + 1
    }
}

extension CalendarDay {
    /// Days from 1970-01-01, proleptic Gregorian (Howard Hinnant's `days_from_civil`). Lenient like the
    /// rest of the type: Feb 30 counts as Mar 2.
    var daysSinceEpoch: Int {
        let shiftedYear = month <= 2 ? year - 1 : year
        let era = (shiftedYear >= 0 ? shiftedYear : shiftedYear - 399) / 400
        let yearOfEra = shiftedYear - era * 400
        let shiftedMonth = month > 2 ? month - 3 : month + 9
        let dayOfYear = (153 * shiftedMonth + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    /// The inverse of `daysSinceEpoch` (`civil_from_days`).
    init(daysSinceEpoch: Int) {
        let shifted = daysSinceEpoch + 719_468
        let era = (shifted >= 0 ? shifted : shifted - 146_096) / 146_097
        let dayOfEra = shifted - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let shiftedMonth = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * shiftedMonth + 2) / 5 + 1
        let month = shiftedMonth < 10 ? shiftedMonth + 3 : shiftedMonth - 9
        self.init(year: yearOfEra + era * 400 + (month <= 2 ? 1 : 0), month: month, day: day)
    }
}

// MARK: - Month grid

/// The days a month calendar draws: six full weeks starting on `firstWeekday`, so every month takes
/// the same height. The month's own days sit among the end of the month before and the start of the
/// month after.
public struct CalendarMonthGrid: Hashable, Sendable {
    public static let weekCount = 6

    public let month: CalendarMonth
    /// 1 = Sunday … 7 = Saturday, normalized into that range.
    public let firstWeekday: Int
    /// `weekCount * 7` consecutive days.
    public let days: [CalendarDay]

    public init(month: CalendarMonth, firstWeekday: Int) {
        let normalizedFirstWeekday = ((firstWeekday - 1) % 7 + 7) % 7 + 1
        let leadingDays = (month.firstDay.weekday - normalizedFirstWeekday + 7) % 7
        let start = month.firstDay.adding(days: -leadingDays)
        self.month = month
        self.firstWeekday = normalizedFirstWeekday
        days = (0 ..< Self.weekCount * 7).map { start.adding(days: $0) }
    }

    /// `days` in rows of seven.
    public var weeks: [[CalendarDay]] {
        stride(from: 0, to: days.count, by: 7).map { Array(days[$0 ..< $0 + 7]) }
    }

    /// The weekday of each column, left to right (1 = Sunday … 7 = Saturday).
    public var weekdayColumns: [Int] {
        (0 ..< 7).map { (firstWeekday - 1 + $0) % 7 + 1 }
    }
}
