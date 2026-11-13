//
//  CalendarDayPicking.swift
//  DateKit
//
//  The rules a day-picking calendar applies where its `CalendarDay` grid meets the `Date` it edits:
//  which day an instant is, which days may be picked, and the instant a pick writes back. Kept apart
//  from any view so every rule is tested on its own, across the zones where days misbehave.
//

import Foundation

/// How a calendar of `CalendarDay`s edits a `Date`.
///
/// Days are read in the Gregorian calendar of `timeZone` (the wall clock the user sees), like
/// `CalendarDay(containing:in:)` everywhere else. A pick keeps the edited date's time of day, so a
/// separate time control bound to the same `Date` is left alone.
///
/// The rule that makes it safe in every zone: a pick only lands if the instant it writes reads back
/// as the picked day. A day the zone skipped entirely (Samoa's 30 December 2011) is not pickable, and
/// a time of day the zone skipped that day (a spring-forward gap) resolves to the first valid instant
/// after it, still on the picked day.
public struct CalendarDayPicking: Sendable {
    /// The years a picker offers. The floor is the first full year of the Gregorian calendar, below
    /// which Foundation's Gregorian calendar counts Julian days and would disagree with
    /// `CalendarMonth`; the ceiling is `CalendarDay.storageString`'s four digits.
    public static let supportedYears = 1583 ... 9999

    /// Gregorian, in the zone whose wall clock names the days.
    public let calendar: Calendar
    public let minimum: Date?
    public let maximum: Date?

    public init(timeZone: TimeZone, minimum: Date? = nil, maximum: Date? = nil) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.calendar = calendar
        self.minimum = minimum
        self.maximum = maximum
    }

    /// The day `instant` falls on.
    public func day(of instant: Date) -> CalendarDay {
        CalendarDay(containing: instant, in: calendar)
    }

    /// The first pickable day: the minimum's day, or the first supported one.
    public var firstDay: CalendarDay {
        let floor = CalendarDay(year: Self.supportedYears.lowerBound, month: 1, day: 1)
        return minimum.map { max(day(of: $0), floor) } ?? floor
    }

    /// The last pickable day: the maximum's day, or the last supported one.
    public var lastDay: CalendarDay {
        let ceiling = CalendarDay(year: Self.supportedYears.upperBound, month: 12, day: 31)
        return maximum.map { min(day(of: $0), ceiling) } ?? ceiling
    }

    /// Whether `day` is inside the bounds. A bound that falls mid-day still allows its whole day; a
    /// pick on it is clamped to the bound (see `instant(picking:keepingTimeOf:)`).
    public func allows(_ day: CalendarDay) -> Bool {
        day.isValid && day >= firstDay && day <= lastDay
    }

    /// Whether any day of `month` is inside the bounds.
    public func allows(_ month: CalendarMonth) -> Bool {
        month.lastDay >= firstDay && month.firstDay <= lastDay
    }

    /// Whether any day of any of `years` is inside the bounds.
    public func allows(years: ClosedRange<Int>) -> Bool {
        CalendarMonth(year: years.upperBound, month: 12).lastDay >= firstDay
            && CalendarMonth(year: years.lowerBound, month: 1).firstDay <= lastDay
    }

    /// Whether a pick of `day` would land: inside the bounds, and a day the zone did not skip.
    public func canPick(_ day: CalendarDay) -> Bool {
        guard allows(day), let noon = day.instant(hour: 12, in: calendar) else { return false }
        return self.day(of: noon) == day
    }

    /// The instant that picking `day` writes: `day` at `current`'s wall-clock time, clamped into the
    /// bounds. nil when the pick cannot land (see `canPick`).
    public func instant(picking day: CalendarDay, keepingTimeOf current: Date) -> Date? {
        guard canPick(day) else { return nil }
        let time = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: current)
        var components = DateComponents()
        components.year = day.year
        components.month = day.month
        components.day = day.day
        components.hour = time.hour
        components.minute = time.minute
        components.second = time.second
        components.nanosecond = time.nanosecond
        var picked = calendar.date(from: components)
        // A time of day the zone skipped can resolve past midnight on a transition day; noon exists
        // on every day `canPick` allows, so it is the fallback that keeps the picked day.
        if picked.map({ self.day(of: $0) }) != day {
            picked = day.instant(hour: 12, in: calendar)
        }
        guard var instant = picked else { return nil }
        if let minimum, instant < minimum {
            instant = minimum
        }
        if let maximum, instant > maximum {
            instant = maximum
        }
        return instant
    }
}

// MARK: - Display

public extension CalendarMonth {
    /// The calendar systems that divide the year into the Gregorian calendar's months and days, so
    /// their month and year names can title a Gregorian month grid (the Buddhist calendar's 2570 is
    /// the Gregorian 2027, month for month). Any other system (Hebrew, Islamic, Persian, Chinese…)
    /// would name a month the grid isn't showing, so those fall back to Gregorian names.
    static let gregorianAlignedCalendars: Set<Calendar.Identifier> = [
        .gregorian, .iso8601, .buddhist, .japanese, .republicOfChina
    ]

    /// The calendar a Gregorian month grid names its months and years in: the user's own system when
    /// it is Gregorian-aligned (the rule `CalendarDay.displayString` keeps, so a picker agrees with
    /// every other date on the screen), Gregorian otherwise. Its zone is UTC, matching the `noonUTC`
    /// anchors it formats.
    static func namingCalendar(for userCalendar: Calendar, locale: Locale) -> Calendar {
        var calendar = gregorianAlignedCalendars.contains(userCalendar.identifier)
            ? Calendar(identifier: userCalendar.identifier)
            : Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = ElapsedTimeBreakdown.utcCalendar.timeZone
        return calendar
    }

    /// "May 2027", "mayo de 2027": the month and its year, in the naming calendar.
    func displayName(locale: Locale, calendar userCalendar: Calendar) -> String {
        let naming = Self.namingCalendar(for: userCalendar, locale: locale)
        return firstDay.noonUTC.formatted(
            Date.FormatStyle(locale: locale, calendar: naming, timeZone: naming.timeZone).month(.wide).year()
        )
    }

    /// The month's name alone ("May", "mayo"), abbreviated when `abbreviated`.
    func monthName(locale: Locale, calendar userCalendar: Calendar, abbreviated: Bool) -> String {
        let naming = Self.namingCalendar(for: userCalendar, locale: locale)
        let names = abbreviated ? naming.shortStandaloneMonthSymbols : naming.standaloneMonthSymbols
        return names.indices.contains(month - 1) ? names[month - 1] : ""
    }

    /// The year this month is in, named in the naming calendar ("2027"; "2570 BE" in the Buddhist
    /// calendar; "Reiwa 9" in the Japanese, whose years Foundation always names with their era).
    func yearName(locale: Locale, calendar userCalendar: Calendar) -> String {
        let naming = Self.namingCalendar(for: userCalendar, locale: locale)
        return firstDay.noonUTC.formatted(
            Date.FormatStyle(locale: locale, calendar: naming, timeZone: naming.timeZone).year()
        )
    }
}
