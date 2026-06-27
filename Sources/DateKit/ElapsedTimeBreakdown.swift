//
//  ElapsedTimeBreakdown.swift
//  DateKit
//
//  The agnostic core of elapsed-time math: a calendar Y/M/D breakdown plus an
//  absolute whole-day count, computed for an arbitrary `[from, to]` interval in
//  an arbitrary `Calendar`. Foundation-only and domain-free — no app concepts,
//  no localization, no `Bundle.module`.
//

import Foundation

/// A calendar breakdown of an elapsed interval: the `years` / `months` / `days`
/// components plus `totalDays`, the absolute whole-day count between the two
/// instants.
///
/// `compute(from:to:calendar:)` is the single source of truth. It is symmetric
/// (a start later than the end is swapped, never producing negative numerals)
/// and clamps every component at zero.
public struct ElapsedTimeBreakdown: Equatable, Hashable, Sendable {
    public let years: Int
    public let months: Int
    public let days: Int
    /// Absolute whole days between `from` and `to`.
    public let totalDays: Int

    /// Memberwise initializer. Public so callers in other modules can construct a
    /// breakdown directly (e.g. fixtures, previews, tests) without going through
    /// `compute`.
    public init(years: Int, months: Int, days: Int, totalDays: Int) {
        self.years = years
        self.months = months
        self.days = days
        self.totalDays = totalDays
    }

    /// The Y/M/D breakdown and absolute whole-day count for the interval between
    /// `from` and `to`, evaluated in `calendar`.
    ///
    /// - The interval is treated as unordered: `min(from, to)` to `max(from, to)`,
    ///   so a future start never renders negative numerals.
    /// - `years` / `months` / `days` come from the calendar's own component math
    ///   (so they respect real month lengths and — in a DST-observing calendar —
    ///   real day boundaries), each clamped at zero.
    /// - `totalDays` is the `.day` component of the same interval: the count of
    ///   whole calendar days. In a no-DST calendar (e.g. ``utcCalendar``) this is
    ///   exactly `floor(elapsedSeconds / 86_400)` measured from the start's
    ///   time-of-day.
    public static func compute(from: Date, to: Date, calendar: Calendar = .current) -> ElapsedTimeBreakdown {
        // Guard against future start dates — never render negative numerals.
        let start = min(from, to)
        let end = max(from, to)
        let comps = calendar.dateComponents([.year, .month, .day], from: start, to: end)
        let total = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        return ElapsedTimeBreakdown(
            years: max(0, comps.year ?? 0),
            months: max(0, comps.month ?? 0),
            days: max(0, comps.day ?? 0),
            totalDays: max(0, total)
        )
    }

    /// A fixed UTC Gregorian calendar (no DST), used for travel-invariant day math.
    ///
    /// Because UTC observes no daylight-saving transitions, every day is exactly
    /// 86 400 seconds, so `compute(..., calendar: .utcCalendar)` produces a day
    /// count that is invariant under the device's time zone and any DST change.
    public static let utcCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()
}
