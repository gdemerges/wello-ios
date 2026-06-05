import Testing
@testable import WelloKit

@Suite("Drink")
struct DrinkTests {

    @Test("eau est le 1ᵉʳ cas et a un coefficient de 1.0")
    func eauDéfaut() {
        #expect(DrinkType.allCases.first == .water)
        #expect(DrinkType.water.defaultCoefficient == 1.0)
    }

    @Test("chaque boisson a un coefficient par défaut dans les bornes")
    func défautsDansBornes() {
        for d in DrinkType.allCases {
            #expect(coefficientRange.contains(d.defaultCoefficient))
        }
    }

    @Test("effectiveHydrationML : eau = identité")
    func eauIdentité() {
        #expect(effectiveHydrationML(volumeML: 500, coefficient: 1.0) == 500)
    }

    @Test("effectiveHydrationML : café 250 × 0.8 = 200")
    func caféEffectif() {
        #expect(effectiveHydrationML(volumeML: 250, coefficient: 0.8) == 200)
    }

    @Test("effectiveHydrationML : spiritueux peut être négatif")
    func spiritueuxNégatif() {
        #expect(effectiveHydrationML(volumeML: 100, coefficient: -0.5) == -50)
    }

    @Test("effectiveHydrationML : arrondi au plus proche")
    func arrondi() {
        #expect(effectiveHydrationML(volumeML: 333, coefficient: 0.9) == 300)   // 299.7 → 300
    }

    @Test("resolveCoefficient : override respecté")
    func overrideRespecté() {
        #expect(resolveCoefficient(default: 0.8, override: 0.95) == 0.95)
    }

    @Test("resolveCoefficient : défaut si pas d'override")
    func défautSiNil() {
        #expect(resolveCoefficient(default: 0.8, override: nil) == 0.8)
    }

    @Test("resolveCoefficient : borné à [-1.0 … 1.5]")
    func bornes() {
        #expect(resolveCoefficient(default: 1.0, override: 9.0) == 1.5)
        #expect(resolveCoefficient(default: 1.0, override: -9.0) == -1.0)
    }

    @Test("clampedDayTotal : négatif → 0, positif inchangé")
    func clamp() {
        #expect(clampedDayTotal(-200) == 0)
        #expect(clampedDayTotal(0) == 0)
        #expect(clampedDayTotal(1500) == 1500)
    }
}
