//
//  AppDates.swift
//  DateKit
//
//  Centralized, agnostic date math + formatting.
//
//  Goals:
//  - One place to define "calendar rules" (whole-day anchoring, DST-safe day
//    boundaries).
//  - Thread-safe formatting using `FormatStyle` (no `DateFormatter`).
//  - Pure functions (easy to test; callers can pass an injected `now`).
//
//  Everything here is Foundation-only and localization-free. Number-to-word
//  pluralization (e.g. "2 days") is a domain concern backed by a string catalog
//  and is intentionally *not* part of this module.
//

import Foundation

// MARK: - Display Types

/// Presets for user-facing date-only formatting.
public enum AppDateStyle: String, CaseIterable, Identifiable, Sendable {
    case short, medium, long
    public var id: String { rawValue }
}

// MARK: - AppDates

/// Namespace for the app-agnostic date math + formatting helpers.
public enum AppDates {

    // MARK: Configuration

    /// The calendar used for calculations: the user's autoupdating locale and
    /// time zone. Day boundaries therefore follow the device's local midnight.
    public static let calendar: Calendar = {
        var cal = Calendar.current
        cal.locale = .autoupdatingCurrent
        cal.timeZone = .autoupdatingCurrent
        return cal
    }()

    // MARK: Time Since

    /// The wall-clock noon of `date`'s calendar day — the anchor used for whole-day
    /// differencing.
    ///
    /// Noon is used instead of `startOfDay` because midnight does not exist on every
    /// day: some zones spring forward *at* 00:00 (America/Santiago, America/Havana,
    /// Atlantic/Azores), so the transition day starts at 01:00 and midnight-floored
    /// differencing under-counts every span touching that day by one. Real-world DST
    /// transitions never skip noon, and every calendar day is 23–25 hours long, so
    /// noon-to-noon component math counts calendar days exactly.
    private static func noon(of date: Date, calendar: Calendar) -> Date {
        var components = calendar.dateComponents([.era, .year, .month, .day], from: date)
        components.hour = 12
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    /// Whole calendar-day difference between two dates (each anchored to its own
    /// calendar day). Timezone-aware day boundaries are the calendar's responsibility;
    /// this is the plain calendar-day helper for cases that don't need a fixed
    /// reference frame.
    ///
    /// - Important: This is the one elapsed helper that is **signed** — reversed
    ///   arguments (`endDate` earlier than `startDate`) yield a negative count.
    ///   Every other helper here (``timeSinceComponents(from:to:calendar:)``,
    ///   ``clockComponents(from:)``, ``compactElapsed(from:to:)``, and
    ///   ``ElapsedTimeBreakdown/compute(from:to:calendar:)``) is unordered and
    ///   clamps at zero. Use this only when you actually want direction.
    public static func daysBetween(
        _ startDate: Date,
        _ endDate: Date,
        calendar: Calendar = AppDates.calendar
    ) -> Int {
        let shiftedStart = noon(of: startDate, calendar: calendar)
        let shiftedEnd   = noon(of: endDate, calendar: calendar)
        return calendar.dateComponents([.day], from: shiftedStart, to: shiftedEnd).day ?? 0
    }

    /// Calendar-style Y/M/D difference, anchored to whole calendar days. When still
    /// within day 0 (no whole years/months/days) the result carries sub-day
    /// granularity (hours/minutes/seconds) instead.
    ///
    /// The interval is treated as unordered — `min` to `max` — so reversed input
    /// yields the same magnitude as forward input (mirroring
    /// ``ElapsedTimeBreakdown/compute(from:to:calendar:)``), never negative numerals.
    public static func timeSinceComponents(
        from startDate: Date,
        to endDate: Date,
        calendar: Calendar = AppDates.calendar
    ) -> TimeSinceComponents {
        // Guard against reversed input — never render negative numerals.
        let lo = min(startDate, endDate)
        let hi = max(startDate, endDate)
        let start = noon(of: lo, calendar: calendar)
        let end = noon(of: hi, calendar: calendar)
        let comps = calendar.dateComponents([.year, .month, .day], from: start, to: end)
        let years = max(0, comps.year ?? 0)
        let months = max(0, comps.month ?? 0)
        let days = max(0, comps.day ?? 0)

        if years == 0 && months == 0 && days == 0 {
            // Provide sub-day granularity when still within day 0.
            let hms = calendar.dateComponents([.hour, .minute, .second], from: lo, to: hi)
            let hours = max(0, hms.hour ?? 0)
            let minutes = max(0, hms.minute ?? 0)
            let seconds = max(0, hms.second ?? 0)
            return TimeSinceComponents(years: 0, months: 0, days: 0, hours: hours, minutes: minutes, seconds: seconds)
        }

        return TimeSinceComponents(years: years, months: months, days: days)
    }

    // MARK: Formatting (FormatStyle-based, thread-safe)

    /// Returns `true` when the date falls exactly on midnight in the given
    /// calendar's time zone. Used to decide whether to show the time component.
    ///
    /// Sub-second precision counts: a date at `00:00:00.5` is **not** midnight, so a
    /// fractional-second time component is never silently dropped by callers that
    /// branch on this.
    public static func isMidnight(_ date: Date, calendar: Calendar = AppDates.calendar) -> Bool {
        let comps = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        return (comps.hour ?? 0) == 0
            && (comps.minute ?? 0) == 0
            && (comps.second ?? 0) == 0
            && (comps.nanosecond ?? 0) == 0
    }

    /// Date + time string when the time is non-midnight, date-only string otherwise.
    /// Example: "June 15, 2022 at 3:45 PM" vs "June 15, 2022".
    public static func dateTimeString(_ date: Date, dateStyle: AppDateStyle) -> String {
        if isMidnight(date) {
            return dateString(date, style: dateStyle)
        }

        let locale = Locale.autoupdatingCurrent
        let timeZone = TimeZone.autoupdatingCurrent
        let calendar = Calendar.autoupdatingCurrent

        let datePart: Date.FormatStyle.DateStyle
        switch dateStyle {
        case .short:  datePart = .numeric
        case .medium: datePart = .abbreviated
        case .long:   datePart = .complete
        }

        return date.formatted(
            Date.FormatStyle(
                date: datePart,
                time: .shortened,
                locale: locale,
                calendar: calendar,
                timeZone: timeZone
            )
        )
    }

    /// User-facing date-only string (localized, thread-safe).
    public static func dateString(_ date: Date, style: AppDateStyle) -> String {
        let locale = Locale.autoupdatingCurrent
        let timeZone = TimeZone.autoupdatingCurrent
        let calendar = Calendar.autoupdatingCurrent

        let dateStyle: Date.FormatStyle.DateStyle
        switch style {
        case .short:
            dateStyle = .numeric
        case .medium:
            dateStyle = .abbreviated
        case .long:
            dateStyle = .complete
        }

        return date.formatted(
            Date.FormatStyle(
                date: dateStyle,
                time: .omitted,
                locale: locale,
                calendar: calendar,
                timeZone: timeZone
            )
        )
    }

    /// The whole hours / minutes / seconds of an elapsed interval, clamped at 0.
    /// The single source for a "live clock" split (e.g. a day-0 counter) so every
    /// surface rolls over identically.
    ///
    /// Non-finite input (`.infinity` / `.nan`) is treated as zero, and finite input
    /// beyond `Int.max` seconds is clamped to `Int.max`, rather than trapping in
    /// `Int(_:)`.
    public static func clockComponents(from interval: TimeInterval) -> (hours: Int, minutes: Int, seconds: Int) {
        guard interval.isFinite else { return (0, 0, 0) }
        let clamped = max(0, interval)
        // `TimeInterval(Int.max)` rounds up to 2^63, so anything below it converts
        // to `Int` without trapping; everything at or above clamps to `Int.max`.
        let totalSeconds = clamped < TimeInterval(Int.max) ? Int(clamped) : Int.max
        return (totalSeconds / 3600, (totalSeconds % 3600) / 60, totalSeconds % 60)
    }

    /// The elapsed hours / minutes / seconds between two dates (`now - start`), clamped at 0.
    public static func clockComponents(since start: Date, to now: Date) -> (hours: Int, minutes: Int, seconds: Int) {
        clockComponents(from: now.timeIntervalSince(start))
    }
}
