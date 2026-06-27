//
//  TimeSinceComponentsTests.swift
//  DateKitTests
//
//  Coverage of the agnostic display breakdown: which units `nonZeroUnits` returns
//  and that zero-valued units are dropped.
//

import XCTest
@testable import DateKit

final class TimeSinceComponentsTests: XCTestCase {

    func testNonZeroUnitsSubDayDropsZeroUnits() {
        let components = TimeSinceComponents(years: 0, months: 0, days: 0, hours: 2, minutes: 0, seconds: 30)
        let units = components.nonZeroUnits
        XCTAssertEqual(units.map(\.kind), [.hours, .seconds]) // minutes == 0 dropped
        XCTAssertEqual(units.map(\.value), [2, 30])
    }

    func testNonZeroUnitsUsesYMDWhenADayHasElapsed() {
        // Any whole year/month/day flips to the Y/M/D set; sub-day units are ignored.
        let components = TimeSinceComponents(years: 1, months: 0, days: 5, hours: 9, minutes: 9, seconds: 9)
        let units = components.nonZeroUnits
        XCTAssertEqual(units.map(\.kind), [.years, .days]) // months == 0 dropped
        XCTAssertEqual(units.map(\.value), [1, 5])
    }

    func testNonZeroUnitsEmptyWhenAllZero() {
        let components = TimeSinceComponents(years: 0, months: 0, days: 0)
        XCTAssertTrue(components.nonZeroUnits.isEmpty)
    }

    func testTimeUnitIdentityIsKindRawValue() {
        XCTAssertEqual(TimeUnit(kind: .minutes, value: 4).id, "minutes")
        XCTAssertEqual(TimeUnit(kind: .years, value: 1).id, TimeUnit.Kind.years.rawValue)
    }

    func testTimeUnitEquatable() {
        XCTAssertEqual(TimeUnit(kind: .days, value: 3), TimeUnit(kind: .days, value: 3))
        XCTAssertNotEqual(TimeUnit(kind: .days, value: 3), TimeUnit(kind: .days, value: 4))
    }
}
