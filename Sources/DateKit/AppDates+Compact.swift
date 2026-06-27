//
//  AppDates+Compact.swift
//  DateKit
//
//  A compact, glanceable elapsed string for tight surfaces (e.g. list rows). Uses
//  `DateComponentsFormatter` so abbreviations and plural grammar are localized by
//  the system in every locale, and uses the shared calendar so year/month respect
//  real month lengths (not 30/365-day approximations).
//

import Foundation

extension AppDates {
    /// The two largest elapsed units, abbreviated — e.g. "4yr 1mo", "1mo 13d", "12d".
    /// Returns a localized day count for same-/sub-day spans. Symmetric in its
    /// arguments (the smaller instant is treated as the start).
    public static func compactElapsed(from start: Date, to end: Date = Date()) -> String {
        let lo = min(start, end)
        let hi = max(start, end)

        let formatter = DateComponentsFormatter()
        formatter.calendar = calendar
        formatter.unitsStyle = .brief
        formatter.allowedUnits = [.year, .month, .day]
        formatter.maximumUnitCount = 2
        formatter.zeroFormattingBehavior = .dropAll

        if let result = formatter.string(from: lo, to: hi), !result.isEmpty {
            return result
        }

        // Same-day / sub-day: show a localized "0 days" rather than an empty string.
        let dayFormatter = DateComponentsFormatter()
        dayFormatter.calendar = calendar
        dayFormatter.unitsStyle = .brief
        dayFormatter.allowedUnits = [.day]
        return dayFormatter.string(from: lo, to: hi) ?? ""
    }
}
