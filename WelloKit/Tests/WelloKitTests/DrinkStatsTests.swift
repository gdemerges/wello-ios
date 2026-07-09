import XCTest
@testable import WelloKit

final class DrinkStatsTests: XCTestCase {
    func testAggregatesByFamilyWithEffectiveHydration() {
        let entries = [
            DrinkStatsEntry(drink: .water, volumeML: 500, effectiveML: 500, hour: 8),
            DrinkStatsEntry(drink: .coffee, volumeML: 250, effectiveML: 200, hour: 9),
            DrinkStatsEntry(drink: .tea, volumeML: 300, effectiveML: 270, hour: 15),
            DrinkStatsEntry(drink: .wine, volumeML: 150, effectiveML: 0, hour: 20),
            DrinkStatsEntry(drink: .spirits, volumeML: 50, effectiveML: -25, hour: 23)
        ]

        let families = DrinkStats.byFamily(entries)
        let caffeine = families.first { $0.family == .caffeine }
        let alcohol = families.first { $0.family == .alcohol }

        XCTAssertEqual(caffeine?.volumeML, 550)
        XCTAssertEqual(caffeine?.effectiveML, 470)
        XCTAssertEqual(caffeine?.dominantPeriod, .apresMidi)
        XCTAssertEqual(alcohol?.volumeML, 200)
        XCTAssertEqual(alcohol?.effectiveML, -25)
        XCTAssertEqual(alcohol?.dominantPeriod, .soiree)
    }

    func testAggregatesByDrinkAndSortsByEffectiveHydration() {
        let entries = [
            DrinkStatsEntry(drink: .coffee, volumeML: 250, effectiveML: 200, hour: 9),
            DrinkStatsEntry(drink: .water, volumeML: 150, effectiveML: 150, hour: 8),
            DrinkStatsEntry(drink: .water, volumeML: 500, effectiveML: 500, hour: 16)
        ]

        let drinks = DrinkStats.byDrink(entries)

        XCTAssertEqual(drinks.map(\.drink), [.water, .coffee])
        XCTAssertEqual(drinks.first?.volumeML, 650)
        XCTAssertEqual(drinks.first?.effectiveML, 650)
        XCTAssertEqual(drinks.first?.dominantPeriod, .apresMidi)
    }
}
