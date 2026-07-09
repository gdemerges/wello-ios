import XCTest
@testable import WelloKit

final class HydrationPaceTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private func date(hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 9, hour: hour, minute: minute))!
    }

    func testExpectedProgressIsLinearAcrossWakeWindow() {
        let pace = HydrationPaceCalculator.evaluate(goalML: 2800, consumedML: 900,
                                                    now: date(hour: 14),
                                                    window: .défaut,
                                                    calendar: calendar)
        XCTAssertEqual(pace.expectedNowML, 1400)
        XCTAssertEqual(pace.remainingML, 1900)
        XCTAssertEqual(pace.glassesToGo, 8)
        XCTAssertEqual(pace.status, .behind)
    }

    func testDoneWhenGoalReached() {
        let pace = HydrationPaceCalculator.evaluate(goalML: 2000, consumedML: 2200,
                                                    now: date(hour: 16),
                                                    calendar: calendar)
        XCTAssertEqual(pace.remainingML, 0)
        XCTAssertEqual(pace.glassesToGo, 0)
        XCTAssertEqual(pace.status, .done)
    }

    func testBeforeWakeWindowDoesNotMarkBehind() {
        let pace = HydrationPaceCalculator.evaluate(goalML: 2000, consumedML: 0,
                                                    now: date(hour: 6),
                                                    calendar: calendar)
        XCTAssertEqual(pace.expectedNowML, 0)
        XCTAssertEqual(pace.status, .notStarted)
    }
}
