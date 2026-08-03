//
//  CalendarDay.swift
//  DateKit
//
//  Extracted from CommittedKit (2026-08-03), where it was minted to end a run of
//  instant-read-in-the-wrong-calendar bugs. Foundation-only, like the rest of DateKit, so apps,
//  widgets, and watch targets can all share it.
//

import Foundation

/// A calendar day — year/month/day only, no time, no zone — the typed replacement for storing a
/// day as a `Date` instant and re-deriving "which day" at every read site.
///
/// An instant-typed day gets re-read through whatever calendar each read site picks — UTC in one
/// place, the local calendar in another, the ambient default in a third — and every site
/// re-decides the convention. In the app this type came from, that mismatch produced four
/// consecutive shipped bugs of the same shape (a stored instant read in the wrong calendar names
/// the neighboring day). `CalendarDay` makes that misread inexpressible: the value carries no
/// instant to misinterpret, and every conversion between a day and an instant names its policy
/// explicitly — `init(containing:in:)` to read an instant *into* a day, and `startOfDayUTC` /
/// `noonUTC` / `instant(hour:minute:in:)` to anchor a day *back* to an instant.
///
/// Components are Gregorian by convention and are normalized nowhere: callers validate, and a
/// Feb 30 in is a Feb 30 out. Consumers that anchor an unvalidated day to an instant inherit the
/// Gregorian calendar's lenient resolve (Feb 30 reads as Mar 2).
public struct CalendarDay: Hashable, Comparable, Sendable, Codable {
    public let year: Int
    public let month: Int
    public let day: Int

    /// Trusts its inputs — no range check, no normalization. The validated entry points are the
    /// UIs that mint days (a DatePicker cannot produce a Feb 30); this initializer exists for
    /// those callers and for tests, and keeps the type a plain value with no hidden policy.
    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// THE local-pick reader: the day `instant` falls on in `calendar`. This is how a DatePicker
    /// buffer, `now`, or a legacy stored instant becomes a day — and the calendar is named at the
    /// call site, never ambient, so "which zone decides the day" is visible in the code that
    /// decides it (the exact decision the old instant-typed reads made silently, and differently).
    public init(containing instant: Date, in calendar: Calendar) {
        let components = calendar.dateComponents([.year, .month, .day], from: instant)
        self.init(year: components.year ?? 0, month: components.month ?? 0, day: components.day ?? 0)
    }
}

// MARK: - Storage form

public extension CalendarDay {
    /// The canonical serialized form: strict `yyyy-MM-dd`, zero-padded, exactly 10 characters.
    /// This exact string is a DB column value and stableID component in consuming apps, so its
    /// format must NEVER change — and it is chosen so that lexicographic string order equals day
    /// order, meaning a SQL `ORDER BY` on the column agrees with `Comparable` by construction.
    ///
    /// The zero-padded form holds for years 1...9999; the storage surface is defined only there
    /// (the domain is contemporary dates, and callers validate).
    var storageString: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Parses the strict storage form and nothing else: exactly 10 ASCII characters, dashes at
    /// positions 4 and 7, digits everywhere else. No `DateFormatter` — the three integer fields
    /// are read directly, so parsing is locale- and zone-proof by construction.
    ///
    /// Validation is FORMAT-strict but range-agnostic: `"2026-13-40"` parses (to month 13, day
    /// 40), because this type trusts its fields everywhere — `init(year:month:day:)` accepts the
    /// same values, and a range check here would make the parser a second, divergent authority on
    /// validity. Shape violations (`"2026-5-2"`, `"2026/05/02"`, a trailing time) are rejected.
    init?(storageString: String) {
        let asciiBytes = Array(storageString.utf8)
        guard asciiBytes.count == 10,
              asciiBytes[4] == UInt8(ascii: "-"),
              asciiBytes[7] == UInt8(ascii: "-")
        else { return nil }

        func parseDigits(in range: Range<Int>) -> Int? {
            var value = 0
            for index in range {
                let byte = asciiBytes[index]
                guard byte >= UInt8(ascii: "0"), byte <= UInt8(ascii: "9") else { return nil }
                value = value * 10 + Int(byte - UInt8(ascii: "0"))
            }
            return value
        }

        guard let year = parseDigits(in: 0 ..< 4),
              let month = parseDigits(in: 5 ..< 7),
              let day = parseDigits(in: 8 ..< 10)
        else { return nil }
        self.init(year: year, month: month, day: day)
    }
}

// MARK: - Codable (single canonical form)

public extension CalendarDay {
    /// Encodes as the single `storageString` — not a keyed Y/M/D container — so every
    /// serialization surface (widget snapshot JSON, backup export, anything Codable touches) gets
    /// the same canonical form as the DB column, and there is exactly one wire format to keep
    /// stable.
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(storageString)
    }

    /// Decoding is as strict as `init?(storageString:)`: malformed input fails the decode rather
    /// than producing a silently-wrong day.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawString = try container.decode(String.self)
        guard let parsed = CalendarDay(storageString: rawString) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Not a strict yyyy-MM-dd calendar day: \(rawString)"
            )
        }
        self = parsed
    }
}

// MARK: - Instant anchors (each policy names its consumer)

public extension CalendarDay {
    /// Midnight UTC of this day — the fixed-anchor policy for identity-bearing instants (keys,
    /// achievement identity, dedup): every consumer derives the same instant from the same day,
    /// on any host, in any zone.
    var startOfDayUTC: Date {
        instantInUTC(hour: 0)
    }

    /// Noon UTC of this day — the "date only" anchor policy CommittedKit's sobriety start
    /// stores; kept byte-identical here (its convergence test lives beside that field) so the
    /// field can move onto `CalendarDay` later with zero schema change.
    var noonUTC: Date {
        instantInUTC(hour: 12)
    }

    /// This day at the given wall-clock time in the given (usually local) calendar — the
    /// fire-time / DatePicker-seed conversion. Returns nil only when the calendar genuinely cannot
    /// resolve the components.
    ///
    /// A components-based resolve is spring-forward-safe: it asks for the WALL-CLOCK time, not
    /// midnight plus elapsed hours (which lands an hour late across a DST gap). On the rare day a
    /// zone skips the requested wall time entirely, the calendar resolves to the first valid
    /// instant after the gap — still the right day.
    func instant(hour: Int, minute: Int = 0, in calendar: Calendar) -> Date? {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)
    }

    /// Shared body of the two UTC anchors, on the single UTC calendar authority
    /// (`ElapsedTimeBreakdown.utcCalendar`). The coalesce is unreachable — the Gregorian calendar
    /// resolves ANY integer components leniently (Feb 30 reads as Mar 2) — and exists only because
    /// `date(from:)` is typed optional.
    private func instantInUTC(hour: Int) -> Date {
        instant(hour: hour, in: ElapsedTimeBreakdown.utcCalendar) ?? Date(timeIntervalSince1970: 0)
    }
}

// MARK: - Day math

public extension CalendarDay {
    /// Signed whole days from `other` to `self` — positive when `self` is later. Computed as
    /// `startOfDayUTC` to `startOfDayUTC` in the fixed UTC calendar, so it is DST-immune by
    /// construction: no local zone is consulted, so no 23- or 25-hour day can ever shave or pad
    /// the count (the bug this replaces read day distances through the ambient-default calendar).
    func days(since other: CalendarDay) -> Int {
        ElapsedTimeBreakdown.utcCalendar.dateComponents(
            [.day],
            from: other.startOfDayUTC,
            to: startOfDayUTC
        ).day ?? 0
    }

    /// Lexicographic (year, month, day) — pure component comparison, no instant and no calendar,
    /// and consistent with both `days(since:)` and `storageString`'s string order.
    static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

// MARK: - Display (which calendar and zone render the day)

public extension CalendarDay {
    /// The user-facing date string: the user's own calendar SYSTEM, with only its time ZONE forced
    /// to UTC.
    ///
    /// The zone override is a storage detail: a day anchor read in the device zone renders the
    /// wrong day (a midnight-UTC anchor names the PREVIOUS day everywhere west of UTC; a noon-UTC
    /// anchor names the NEXT day east of UTC+12 — a shipped Auckland "Jan 3 under a Jan 2 count"
    /// bug). Formatting `startOfDayUTC` under a UTC zone is an identity read of the stored Y-M-D,
    /// so the string names THIS day in every zone.
    ///
    /// What must NOT be overridden is which calendar system does the naming. Hard-coding the
    /// Gregorian `utcCalendar` here showed a Buddhist-calendar user "2026" where every other date
    /// in the same screen said "2569" — one screen disagreeing with itself. Only the zone is a
    /// storage detail; the era and year are the user's.
    ///
    /// Uncached `Date.FormatStyle`, thread-safe by design (no `DateFormatter`), with the style
    /// mapping mirroring `AppDates.dateString` exactly.
    ///
    /// - Parameter calendar: the user's calendar system. Defaults to the ambient
    ///   `.autoupdatingCurrent`; its zone is ignored (and replaced), so only the system matters.
    func displayString(
        style: AppDateStyle,
        locale: Locale = .autoupdatingCurrent,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        var renderCalendar = calendar
        renderCalendar.timeZone = ElapsedTimeBreakdown.utcCalendar.timeZone
        let datePart: Date.FormatStyle.DateStyle = switch style {
        case .short: .numeric
        case .medium: .abbreviated
        case .long: .complete
        }
        return startOfDayUTC.formatted(Date.FormatStyle(
            date: datePart,
            time: .omitted,
            locale: locale,
            calendar: renderCalendar,
            timeZone: renderCalendar.timeZone
        ))
    }
}
