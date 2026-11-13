//
//  CalendarPicker.swift
//  DateKitUI
//
//  A month calendar for picking a day, built on DateKit's `CalendarDay` grid. Its days are counted,
//  never stepped through as instants, so a zone whose day starts at 01:00 or skips a date cannot
//  misdraw a month; the one place a pick meets the `Date` it edits is `CalendarDayPicking`, where
//  every rule is tested.
//
//  Its shape follows the iPhone's calendar: a month of days, whose title opens the twelve months,
//  whose title opens a page of years. Colors, fonts and the VoiceOver labels come from the caller
//  (`CalendarPickerAppearance`, `CalendarPickerLabels`), so the calendar takes on an app's look and
//  speaks its language without DateKit carrying a theme or a strings table.
//

import DateKit
import SwiftUI

/// A month calendar that picks the day of `selection`, keeping its time of day.
public struct CalendarPicker: View {
    @Binding private var selection: Date
    private let minimumDate: Date?
    private let maximumDate: Date?
    private let appearance: CalendarPickerAppearance
    private let labels: CalendarPickerLabels

    @Environment(\.calendar) private var userCalendar
    @Environment(\.timeZone) private var timeZone
    @Environment(\.locale) private var locale

    @State private var mode: Mode = .days
    @State private var navigation: Navigation?
    @State private var yearPageStart = 0
    @State private var hoveredDay: CalendarDay?

    /// - Parameters:
    ///   - selection: the date whose day is picked. A pick keeps its time of day, so a separate time
    ///     control bound to the same date is left alone.
    ///   - minimumDate: the earliest pickable moment; its whole day is pickable. nil = unbounded.
    ///   - maximumDate: the latest pickable moment; its whole day is pickable. nil = unbounded.
    public init(
        selection: Binding<Date>,
        minimumDate: Date? = nil,
        maximumDate: Date? = nil,
        appearance: CalendarPickerAppearance = CalendarPickerAppearance(),
        labels: CalendarPickerLabels = CalendarPickerLabels()
    ) {
        _selection = selection
        self.minimumDate = minimumDate
        self.maximumDate = maximumDate
        self.appearance = appearance
        self.labels = labels
    }

    private enum Mode {
        case days
        case months
        case years
    }

    /// A month the user moved to, remembered with the selected day it was moved from: once the
    /// selection is another day (a pick, or an edit elsewhere), the calendar follows the selection.
    private struct Navigation: Equatable {
        let month: CalendarMonth
        let selectedDay: CalendarDay
    }

    /// What one render reads, worked out once.
    private struct Context {
        let picking: CalendarDayPicking
        let selectedDay: CalendarDay
        let today: CalendarDay
        let shownMonth: CalendarMonth
    }

    private enum Metrics {
        static let dayDiameter: CalendarPickerMetric = 36
        static let columnWidth: CalendarPickerMetric = 40
        static let rowSpacing: CalendarPickerMetric = 2
        static let weekdayRowHeight: CalendarPickerMetric = 22
        static let headerSpacing: CalendarPickerMetric = 10
        static let chooserColumns = 3
        static let chooserRows = 4
        static let chooserSpacing: CalendarPickerMetric = 8
        static let yearsPerPage = chooserColumns * chooserRows
        /// Years before the shown one on a fresh page of years, so the page also reaches ahead.
        static let yearsBeforeShown = 7
        static var width: CalendarPickerMetric {
            columnWidth * 7
        }

        /// The weekday row and six weeks. Every mode takes this height, so switching modes never moves
        /// what sits under the calendar.
        static var bodyHeight: CalendarPickerMetric {
            weekdayRowHeight + (dayDiameter + rowSpacing) * CalendarPickerMetric(CalendarMonthGrid.weekCount)
        }
    }

    public var body: some View {
        let context = makeContext()
        VStack(spacing: Metrics.headerSpacing) {
            header(context)
            Group {
                switch mode {
                case .days: dayGrid(context)
                case .months: monthGrid(context)
                case .years: yearGrid(context)
                }
            }
            .frame(width: Metrics.width, height: Metrics.bodyHeight, alignment: .top)
        }
        .frame(width: Metrics.width)
    }

    private func makeContext() -> Context {
        let picking = CalendarDayPicking(timeZone: timeZone, minimum: minimumDate, maximum: maximumDate)
        let selectedDay = picking.day(of: selection)
        let shownMonth = if let navigation, navigation.selectedDay == selectedDay {
            navigation.month
        } else {
            CalendarMonth(containing: selectedDay)
        }
        return Context(picking: picking, selectedDay: selectedDay, today: picking.day(of: Date()), shownMonth: shownMonth)
    }

    private func show(_ month: CalendarMonth, from context: Context) {
        navigation = Navigation(month: month, selectedDay: context.selectedDay)
    }

    // MARK: - Header

    private func header(_ context: Context) -> some View {
        HStack(spacing: 2) {
            Button { advanceMode(context) } label: {
                HStack(spacing: 6) {
                    Text(verbatim: title(context))
                        .font(appearance.titleFont)
                        .foregroundStyle(mode == .days ? appearance.primary : appearance.accent)
                        .lineLimit(1)
                    Image(systemName: mode == .days ? "chevron.forward" : "chevron.down")
                        .font(appearance.titleFont)
                        .imageScale(.small)
                        .foregroundStyle(appearance.accent)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(hint)

            Spacer(minLength: 8)

            stepButton("chevron.backward", label: stepLabels.previous, offset: -1, context: context)
            stepButton("chevron.forward", label: stepLabels.next, offset: 1, context: context)
        }
    }

    private func stepButton(_ systemName: String, label: Text, offset: Int, context: Context) -> some View {
        let isEnabled = canStep(offset, context: context)
        return Button { step(offset, context: context) } label: {
            Image(systemName: systemName)
                .font(appearance.titleFont)
                .foregroundStyle(isEnabled ? appearance.accent : appearance.tertiary)
                .frame(width: 30, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }

    private func title(_ context: Context) -> String {
        switch mode {
        case .days:
            return context.shownMonth.displayName(locale: locale, calendar: userCalendar)
        case .months:
            return context.shownMonth.yearName(locale: locale, calendar: userCalendar)
        case .years:
            let first = CalendarMonth(year: yearPageStart, month: 1).yearName(locale: locale, calendar: userCalendar)
            let last = CalendarMonth(year: yearPageStart + Metrics.yearsPerPage - 1, month: 12)
                .yearName(locale: locale, calendar: userCalendar)
            return "\(first) – \(last)"
        }
    }

    private var hint: Text {
        switch mode {
        case .days: labels.chooseMonthAndYear
        case .months: labels.chooseYear
        case .years: labels.chooseMonth
        }
    }

    private var stepLabels: (previous: Text, next: Text) {
        switch mode {
        case .days: (labels.previousMonth, labels.nextMonth)
        case .months: (labels.previousYear, labels.nextYear)
        case .years: (labels.earlierYears, labels.laterYears)
        }
    }

    /// The title steps out a level, days → months → years, and from the years back to the months.
    private func advanceMode(_ context: Context) {
        withAnimation(.easeInOut(duration: 0.15)) {
            switch mode {
            case .days:
                mode = .months
            case .months:
                yearPageStart = firstYearOfPage(containing: context.shownMonth.year, picking: context.picking)
                mode = .years
            case .years:
                mode = .months
            }
        }
    }

    /// A page of years that holds `year`, a few years in, kept inside the pickable years where it can
    /// be: with a maximum in 2027, the page ends at 2027 rather than offering years past it.
    private func firstYearOfPage(containing year: Int, picking: CalendarDayPicking) -> Int {
        let lowest = picking.firstDay.year
        let highest = max(lowest, picking.lastDay.year - Metrics.yearsPerPage + 1)
        return min(max(year - Metrics.yearsBeforeShown, lowest), highest)
    }

    private func step(_ offset: Int, context: Context) {
        switch mode {
        case .days:
            show(context.shownMonth.adding(months: offset), from: context)
        case .months:
            show(context.shownMonth.adding(years: offset), from: context)
        case .years:
            yearPageStart += offset * Metrics.yearsPerPage
        }
    }

    private func canStep(_ offset: Int, context: Context) -> Bool {
        switch mode {
        case .days:
            return context.picking.allows(context.shownMonth.adding(months: offset))
        case .months:
            let year = context.shownMonth.year + offset
            return context.picking.allows(years: year ... year)
        case .years:
            let start = yearPageStart + offset * Metrics.yearsPerPage
            return context.picking.allows(years: start ... start + Metrics.yearsPerPage - 1)
        }
    }

    // MARK: - Days

    private func dayGrid(_ context: Context) -> some View {
        let grid = CalendarMonthGrid(month: context.shownMonth, firstWeekday: userCalendar.firstWeekday)
        let weekdayNames = weekdaySymbols()
        return VStack(spacing: Metrics.rowSpacing) {
            HStack(spacing: 0) {
                ForEach(grid.weekdayColumns, id: \.self) { weekday in
                    Text(verbatim: weekdayNames.indices.contains(weekday - 1) ? weekdayNames[weekday - 1] : "")
                        .font(appearance.weekdayFont)
                        .tracking(appearance.weekdayTracking)
                        .textCase(appearance.weekdayCase)
                        .foregroundStyle(appearance.tertiary)
                        .lineLimit(1)
                        .frame(width: Metrics.columnWidth, height: Metrics.weekdayRowHeight)
                }
            }
            .accessibilityHidden(true)
            ForEach(grid.weeks, id: \.self) { week in
                HStack(spacing: 0) {
                    ForEach(week, id: \.self) { day in
                        dayCell(day, inMonth: grid.month.contains(day), context: context)
                            .frame(width: Metrics.columnWidth)
                    }
                }
            }
        }
    }

    private func dayCell(_ day: CalendarDay, inMonth: Bool, context: Context) -> some View {
        let isSelected = day == context.selectedDay
        let isToday = day == context.today
        let isPickable = context.picking.canPick(day)
        let isHovered = hoveredDay == day && isPickable && !isSelected
        let foreground: Color = if isSelected {
            appearance.onAccent
        } else if !isPickable {
            appearance.tertiary.opacity(0.6)
        } else if !inMonth {
            appearance.tertiary
        } else if isToday {
            appearance.accent
        } else {
            appearance.primary
        }

        return Button { pick(day, context: context) } label: {
            Text(day.day, format: .number.grouping(.never))
                .font(appearance.dayFont)
                .monospacedDigit()
                .foregroundStyle(foreground)
                .frame(width: Metrics.dayDiameter, height: Metrics.dayDiameter)
                .background {
                    Circle().fill(isSelected ? appearance.accent : (isHovered ? appearance.highlight : .clear))
                }
                .overlay {
                    if isToday, !isSelected {
                        Circle().strokeBorder(appearance.accent.opacity(0.55), lineWidth: 1)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isPickable)
        #if os(macOS) || os(iOS) || os(visionOS)
            .onHover { isHovering in
                if isHovering {
                    hoveredDay = day
                } else if hoveredDay == day {
                    hoveredDay = nil
                }
            }
        #endif
            .accessibilityLabel(Text(verbatim: day.displayString(style: .long, locale: locale, calendar: userCalendar)))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func pick(_ day: CalendarDay, context: Context) {
        guard let picked = context.picking.instant(picking: day, keepingTimeOf: selection) else { return }
        selection = picked
    }

    /// Weekday names in the locale, indexed by weekday − 1 (Sunday first), Gregorian like the grid.
    private func weekdaySymbols() -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        return calendar.shortStandaloneWeekdaySymbols
    }

    // MARK: - Months and years

    private func monthGrid(_ context: Context) -> some View {
        let year = context.shownMonth.year
        let selectedMonth = CalendarMonth(containing: context.selectedDay)
        return chooserGrid { index in
            let month = CalendarMonth(year: year, month: index + 1)
            chooserCell(
                month.monthName(locale: locale, calendar: userCalendar, abbreviated: true),
                isSelected: month == selectedMonth,
                isEnabled: context.picking.allows(month)
            ) {
                show(month, from: context)
                withAnimation(.easeInOut(duration: 0.15)) { mode = .days }
            }
        }
    }

    private func yearGrid(_ context: Context) -> some View {
        chooserGrid { index in
            let year = yearPageStart + index
            chooserCell(
                CalendarMonth(year: year, month: 1).yearName(locale: locale, calendar: userCalendar),
                isSelected: year == context.selectedDay.year,
                isEnabled: context.picking.allows(years: year ... year)
            ) {
                // The shown month in the picked year, moved inside the bounds when it falls outside.
                var month = CalendarMonth(year: year, month: context.shownMonth.month)
                if month.lastDay < context.picking.firstDay {
                    month = CalendarMonth(containing: context.picking.firstDay)
                } else if month.firstDay > context.picking.lastDay {
                    month = CalendarMonth(containing: context.picking.lastDay)
                }
                show(month, from: context)
                withAnimation(.easeInOut(duration: 0.15)) { mode = .months }
            }
        }
    }

    /// Twelve cells, three across and four down, filling the same height as the days.
    private func chooserGrid<Cell: View>(@ViewBuilder cell: @escaping (Int) -> Cell) -> some View {
        let spacing = Metrics.chooserSpacing
        let rows = CalendarPickerMetric(Metrics.chooserRows)
        let rowHeight = (Metrics.bodyHeight - spacing * (rows - 1)) / rows
        return Grid(horizontalSpacing: spacing, verticalSpacing: spacing) {
            ForEach(0 ..< Metrics.chooserRows, id: \.self) { row in
                GridRow {
                    ForEach(0 ..< Metrics.chooserColumns, id: \.self) { column in
                        cell(row * Metrics.chooserColumns + column)
                            .frame(maxWidth: .infinity)
                            .frame(height: rowHeight)
                    }
                }
            }
        }
    }

    private func chooserCell(
        _ title: String,
        isSelected: Bool,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(appearance.chooserFont)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(isSelected ? appearance.onAccent : (isEnabled ? appearance.primary : appearance.tertiary))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? appearance.accent : appearance.highlight)
                )
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The calendar's layout unit.
typealias CalendarPickerMetric = CGFloat
