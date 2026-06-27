# DateKit

Small, dependency-free Swift package for **elapsed-time math and date formatting**.
Foundation only — no app concepts, no localization tables, no `Bundle.module`. It is
the agnostic core extracted from a real app so the same date math can be shared by an
app, its widgets, and a watch target without dragging any domain code along.

```swift
import DateKit

let breakdown = ElapsedTimeBreakdown.compute(
    from: startDate,
    to: .now,
    calendar: .current
)
// breakdown.years / .months / .days / .totalDays
```

## Table of contents

- [Why this exists](#why-this-exists)
- [What this package is (and isn't)](#what-this-package-is-and-isnt)
- [Requirements](#requirements)
- [Installation](#installation)
- [Public API](#public-api)
  - [`ElapsedTimeBreakdown`](#elapsedtimebreakdown)
  - [`TimeSinceComponents` & `TimeUnit`](#timesincecomponents--timeunit)
  - [`AppDates`](#appdates)
  - [`AppDateStyle`](#appdatestyle)
- [Key behaviors](#key-behaviors)
- [Testing](#testing)
- [License](#license)

## Why this exists

Elapsed-time math is deceptively easy to get wrong:

- **DST.** "How many days between these two dates?" is a *calendar* question, not
  `interval / 86_400`. Across a spring-forward boundary a local day is 23 hours, so
  the naive division is off by one.
- **Travel.** A streak counter that ticks at "local midnight" jumps around when the
  user crosses time zones, unless you anchor the math to a stable reference.
- **Source-of-truth drift.** When an app, its widgets, and a watch app each do their
  own date arithmetic, they disagree by a day at the worst possible moment.

DateKit centralizes the calendar rules in a handful of small, pure, fully tested
functions so every surface computes the same answer.

## What this package is (and isn't)

**This package is:**

- Pure, deterministic, injectable date math (you pass the `Calendar` and the `now`).
- Thread-safe formatting via `FormatStyle` / `DateComponentsFormatter` (no shared
  `DateFormatter`).
- Zero external dependencies — Foundation only.

**This package is _not_:**

- A localization layer. It never turns a number into a *word* ("2 days"). Pluralized,
  string-catalog–backed labels are a domain concern and belong in the consuming
  module (typically as an extension on `TimeUnit`).
- Opinionated about *your* domain. There is no notion of a "commitment", a "sobriety
  date", or a "milestone" here — those conveniences live in the app that adopts DateKit.

## Requirements

| Platform   | Minimum |
| ---------- | ------- |
| iOS        | 16      |
| macOS      | 13      |
| watchOS    | 9       |
| tvOS       | 16      |
| visionOS   | 1       |

Built with **swift-tools 6.0** and compiled in **Swift 6 language mode** (full strict
concurrency). The floor is driven by `Date.FormatStyle`, which needs iOS 16 / macOS 13.

## Installation

Swift Package Manager:

```swift
.package(url: "https://github.com/DaveJabe/DateKit.git", from: "1.0.0")
```

…or a local path during development:

```swift
.package(path: "../DateKit")
```

Then add `"DateKit"` to your target's `dependencies`.

## Public API

### `ElapsedTimeBreakdown`

A calendar breakdown of an interval — the `years` / `months` / `days` components plus
`totalDays`, the absolute whole-day count.

```swift
public struct ElapsedTimeBreakdown: Equatable, Hashable, Sendable {
    public let years: Int
    public let months: Int
    public let days: Int
    public let totalDays: Int

    public init(years: Int, months: Int, days: Int, totalDays: Int)

    /// The single source of truth. Symmetric (a future `from` is swapped, never
    /// negative) and clamped at zero on every component.
    public static func compute(from: Date, to: Date, calendar: Calendar = .current) -> ElapsedTimeBreakdown

    /// A fixed UTC Gregorian calendar (no DST) for travel-invariant day math.
    public static let utcCalendar: Calendar
}
```

`compute` uses the calendar's own component math, so:

- In a **DST-observing calendar**, `totalDays` and `days` count *calendar* days and
  survive spring-forward / fall-back transitions.
- In **`utcCalendar`**, every day is exactly 86 400 seconds, so `totalDays` equals
  `floor(elapsedSeconds / 86_400)` measured from the start's time-of-day — a count
  that does not move when the device's time zone changes.

```swift
// Travel-invariant "whole 24-hour periods" since an exact instant:
let days = ElapsedTimeBreakdown
    .compute(from: start, to: .now, calendar: .utcCalendar)
    .totalDays
```

### `TimeSinceComponents` & `TimeUnit`

A display-oriented breakdown and its individual units.

```swift
public struct TimeSinceComponents: Equatable, Sendable {
    public let years, months, days, hours, minutes, seconds: Int
    public init(years: Int, months: Int, days: Int, hours: Int = 0, minutes: Int = 0, seconds: Int = 0)

    /// Non-zero units in display order: Y/M/D once a day has elapsed, otherwise the
    /// sub-day H/M/S set. Zero-valued units are dropped.
    public var nonZeroUnits: [TimeUnit]
}

public struct TimeUnit: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable { case years, months, days, hours, minutes, seconds }
    public let kind: Kind
    public let value: Int
    public init(kind: Kind, value: Int)
    public var id: String { kind.rawValue }
}
```

> `TimeUnit` deliberately has no `word` / localized-label property — that depends on a
> string catalog and is a domain concern. Add it in your app:
>
> ```swift
> extension TimeUnit {
>     public var word: String { MyStrings.unitLabel(kind: kind, count: value) }
> }
> ```

### `AppDates`

A namespace of pure date helpers.

```swift
public enum AppDates {
    /// The user's autoupdating locale + time zone calendar.
    public static let calendar: Calendar

    /// Whole calendar-day difference (both dates floored to calendar midnight). Signed.
    public static func daysBetween(_ start: Date, _ end: Date, calendar: Calendar = AppDates.calendar) -> Int

    /// Y/M/D difference anchored to midnight, with sub-day H/M/S granularity on day 0.
    public static func timeSinceComponents(from: Date, to: Date, calendar: Calendar = AppDates.calendar) -> TimeSinceComponents

    /// True when the date is exactly midnight in the calendar's time zone.
    public static func isMidnight(_ date: Date, calendar: Calendar = AppDates.calendar) -> Bool

    /// Localized, thread-safe date-only string.
    public static func dateString(_ date: Date, style: AppDateStyle) -> String

    /// Date + time when non-midnight, date-only otherwise.
    public static func dateTimeString(_ date: Date, dateStyle: AppDateStyle) -> String

    /// Whole H/M/S of an interval (or `now - start`), clamped at 0.
    public static func clockComponents(from interval: TimeInterval) -> (hours: Int, minutes: Int, seconds: Int)
    public static func clockComponents(since start: Date, to now: Date) -> (hours: Int, minutes: Int, seconds: Int)

    /// The two largest elapsed units, abbreviated and system-localized — "4yr 1mo",
    /// "1mo 13d", "12d". Symmetric in its arguments.
    public static func compactElapsed(from start: Date, to end: Date = Date()) -> String
}
```

`daysBetween` answers a *calendar-day* question (floored to midnight, so two instants
90 minutes apart that straddle midnight are "1 day"), whereas
`ElapsedTimeBreakdown.compute` counts *whole 24-hour periods*. Pick the one that
matches the question you're asking.

### `AppDateStyle`

```swift
public enum AppDateStyle: String, CaseIterable, Identifiable, Sendable { case short, medium, long }
```

Maps to `Date.FormatStyle.DateStyle` `.numeric` / `.abbreviated` / `.complete`.

## Key behaviors

- **No negative numerals.** `compute` and the `AppDates` component helpers swap a
  future start and clamp every field at zero.
- **`daysBetween` is signed.** It is the one helper that preserves direction (reversed
  arguments give a negative count); everything else is unordered.
- **DST-correct.** Calendar-day counts come from `Calendar.dateComponents`, not from
  dividing seconds, so they're right across DST transitions.
- **Travel-invariant option.** `utcCalendar` gives a day count that never shifts with
  the device time zone.
- **Thread-safe formatting.** All string output uses `FormatStyle` /
  `DateComponentsFormatter`, never a mutable shared `DateFormatter`.

## Testing

```sh
swift test
```

The suite is deterministic: every date is constructed in a fixed calendar (UTC, or an
explicit `America/New_York` calendar for DST cases), and `compactElapsed` is asserted
via locale-independent properties. It covers `compute` over known intervals (including
leap years, the UTC whole-24h boundary, and spring-forward / fall-back day counts),
`daysBetween`, `timeSinceComponents`, `clockComponents`, `isMidnight`, `compactElapsed`,
and the `TimeSinceComponents` / `TimeUnit` display logic.

## License

MIT — see [LICENSE](LICENSE). Copyright (c) 2026 David Jabech.
