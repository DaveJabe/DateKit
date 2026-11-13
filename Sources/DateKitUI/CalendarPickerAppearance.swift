//
//  CalendarPickerAppearance.swift
//  DateKitUI
//
//  What the caller supplies so `CalendarPicker` looks and speaks like its app: colors and fonts, and
//  the VoiceOver labels in the app's own language. DateKit carries no theme and no strings table, so
//  the defaults are system colors and plain English.
//

import SwiftUI

/// The colors and fonts `CalendarPicker` draws with.
public struct CalendarPickerAppearance {
    /// The selected day's fill, today's ring, the header's arrows and open title.
    public var accent: Color
    /// Text on the accent fill.
    public var onAccent: Color
    /// Days of the shown month, the title, the month and year names.
    public var primary: Color
    /// Kept for callers that tint secondary text; the calendar itself draws in the other roles.
    public var secondary: Color
    /// Weekday names, days of the neighboring months, anything that can't be picked.
    public var tertiary: Color
    /// The hover wash on a day, and the resting fill of the month and year cells.
    public var highlight: Color

    public var titleFont: Font
    public var weekdayFont: Font
    public var weekdayCase: Text.Case?
    public var weekdayTracking: CGFloat
    public var dayFont: Font
    public var chooserFont: Font

    public init(
        accent: Color = .accentColor,
        onAccent: Color = .white,
        primary: Color = .primary,
        secondary: Color = .secondary,
        tertiary: Color = .secondary.opacity(0.55),
        highlight: Color = .primary.opacity(0.08),
        titleFont: Font = .headline,
        weekdayFont: Font = .caption2,
        weekdayCase: Text.Case? = .uppercase,
        weekdayTracking: CGFloat = 0,
        dayFont: Font = .body,
        chooserFont: Font = .body
    ) {
        self.accent = accent
        self.onAccent = onAccent
        self.primary = primary
        self.secondary = secondary
        self.tertiary = tertiary
        self.highlight = highlight
        self.titleFont = titleFont
        self.weekdayFont = weekdayFont
        self.weekdayCase = weekdayCase
        self.weekdayTracking = weekdayTracking
        self.dayFont = dayFont
        self.chooserFont = chooserFont
    }
}

/// The calendar's VoiceOver labels and hints. Pass `Text` built in the app (`Text("Previous month")`)
/// so each resolves through the app's own strings table.
public struct CalendarPickerLabels {
    public var previousMonth: Text
    public var nextMonth: Text
    public var previousYear: Text
    public var nextYear: Text
    public var earlierYears: Text
    public var laterYears: Text
    /// The hint on the title while it shows a month of days.
    public var chooseMonthAndYear: Text
    /// The hint on the title while it shows the twelve months.
    public var chooseYear: Text
    /// The hint on the title while it shows a page of years.
    public var chooseMonth: Text

    public init(
        previousMonth: Text = Text(verbatim: "Previous month"),
        nextMonth: Text = Text(verbatim: "Next month"),
        previousYear: Text = Text(verbatim: "Previous year"),
        nextYear: Text = Text(verbatim: "Next year"),
        earlierYears: Text = Text(verbatim: "Earlier years"),
        laterYears: Text = Text(verbatim: "Later years"),
        chooseMonthAndYear: Text = Text(verbatim: "Choose month and year"),
        chooseYear: Text = Text(verbatim: "Choose year"),
        chooseMonth: Text = Text(verbatim: "Choose month")
    ) {
        self.previousMonth = previousMonth
        self.nextMonth = nextMonth
        self.previousYear = previousYear
        self.nextYear = nextYear
        self.earlierYears = earlierYears
        self.laterYears = laterYears
        self.chooseMonthAndYear = chooseMonthAndYear
        self.chooseYear = chooseYear
        self.chooseMonth = chooseMonth
    }
}
