//
//  SendabilityTests.swift
//  DateKitTests
//
//  Compile-time + runtime locks on the `Sendable` conformance of the public value
//  types. The package was extracted so the same date values can cross target and
//  actor boundaries (app ↔ widget ↔ watch); these tests fail to *compile* if any
//  of those types loses `Sendable`.
//

import XCTest
@testable import DateKit

final class SendabilityTests: XCTestCase {

    /// Compiles only if `Value` is `Sendable`.
    private func requireSendable<Value: Sendable>(_ value: Value) -> Value { value }

    func testPublicValueTypesAreSendable() async {
        let breakdown = requireSendable(ElapsedTimeBreakdown(years: 1, months: 2, days: 3, totalDays: 400))
        let components = requireSendable(TimeSinceComponents(years: 1, months: 2, days: 3, hours: 4, minutes: 5, seconds: 6))
        let unit = requireSendable(TimeUnit(kind: .days, value: 3))
        let style = requireSendable(AppDateStyle.long)

        // Capturing these in a `Task` (a @Sendable closure crossing isolation) is the
        // real cross-actor send the conformance exists for; in Swift 6 language mode
        // this won't compile if a captured value is non-Sendable.
        let roundTripped = await Task {
            (breakdown, components, unit, style)
        }.value

        XCTAssertEqual(roundTripped.0, breakdown)
        XCTAssertEqual(roundTripped.1, components)
        XCTAssertEqual(roundTripped.2, unit)
        XCTAssertEqual(roundTripped.3, style)
    }
}
