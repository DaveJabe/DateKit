//
//  TimeSinceComponents.swift
//  DateKit
//
//  Agnostic, display-oriented breakdown of elapsed time and its individual units.
//  Foundation-only and localization-free — the *number* and *kind* of each unit,
//  not its localized word. (A localized word for a `TimeUnit` is a domain concern
//  and belongs to the consuming module.)
//

import Foundation

/// Calendar-style breakdown of elapsed time.
public struct TimeSinceComponents: Equatable, Sendable {
    public let years: Int
    public let months: Int
    public let days: Int
    public let hours: Int
    public let minutes: Int
    public let seconds: Int

    public init(years: Int, months: Int, days: Int, hours: Int = 0, minutes: Int = 0, seconds: Int = 0) {
        self.years = years
        self.months = months
        self.days = days
        self.hours = hours
        self.minutes = minutes
        self.seconds = seconds
    }

    /// Non-zero components in display order.
    ///
    /// While still within day 0 (no whole years/months/days) the sub-day units are
    /// returned (hours → minutes → seconds); once a day has elapsed the Y/M/D units
    /// are returned. Zero-valued units are dropped from whichever set is chosen.
    public var nonZeroUnits: [TimeUnit] {
        if years == 0 && months == 0 && days == 0 {
            return [
                TimeUnit(kind: .hours, value: hours),
                TimeUnit(kind: .minutes, value: minutes),
                TimeUnit(kind: .seconds, value: seconds)
            ].filter { $0.value > 0 }
        } else {
            return [
                TimeUnit(kind: .years, value: years),
                TimeUnit(kind: .months, value: months),
                TimeUnit(kind: .days, value: days)
            ].filter { $0.value > 0 }
        }
    }
}

/// A single time unit and its value, suitable for UI display.
///
/// The localized *word* for a unit (e.g. "day" / "days") depends on a string
/// catalog and is therefore a domain concern; the consuming module is expected to
/// add it via an extension (e.g. `extension TimeUnit { var word: String { … } }`).
public struct TimeUnit: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable {
        case years, months, days
        case hours, minutes, seconds
    }

    public let kind: Kind
    public let value: Int

    public init(kind: Kind, value: Int) {
        self.kind = kind
        self.value = value
    }

    public var id: String { kind.rawValue }
}
