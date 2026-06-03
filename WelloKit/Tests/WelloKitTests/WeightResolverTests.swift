import Testing
@testable import WelloKit

@Suite("WeightResolver")
struct WeightResolverTests {

    @Test("Utilise le poids HealthKit quand disponible")
    func utiliseHealthKit() {
        #expect(résoudrePoids(healthKitKg: 72.5, profilKg: 80) == 72.5)
    }

    @Test("Fallback sur le poids du profil quand HealthKit est absent")
    func fallbackProfil() {
        #expect(résoudrePoids(healthKitKg: nil, profilKg: 80) == 80)
    }

    @Test("Ignore un poids HealthKit non plausible (≤ 0)")
    func ignoreValeurAberrante() {
        #expect(résoudrePoids(healthKitKg: 0, profilKg: 80) == 80)
    }
}
