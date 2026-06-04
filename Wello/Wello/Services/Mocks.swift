import Foundation
import WelloKit

/// Implémentations factices pour les SwiftUI previews et le développement hors device.
struct MockHealthKitService: HealthKitServicing {
    var énergieKcal: Double = 320
    var poids: Double? = 78
    func requestAuthorization() async {}
    func énergieActiveDuJour() async -> Double { énergieKcal }
    func dernierPoids() async -> Double? { poids }
    func écrireEau(ml: Int, date: Date) async {}
    func supprimerEau(ml: Int, date: Date) async {}
    func prisesEauExternes(depuis date: Date) async -> [PriseEauExterne] { [] }
    func dernierWorkoutTerminé() async -> Date? { nil }
}

struct MockWeatherService: WeatherServicing {
    var snapshot: WeatherSnapshot? = WeatherSnapshot(apparentTemperatureC: 33)
    func météoDuJour(latitude: Double, longitude: Double) async -> WeatherSnapshot? { snapshot }
}

struct MockLocationService: LocationServicing {
    var coords: (latitude: Double, longitude: Double)? = (48.85, 2.35)
    func coordonnéesActuelles() async -> (latitude: Double, longitude: Double)? { coords }
}

struct MockNotificationService: NotificationServicing {
    func requestAuthorization() async -> Bool { true }
    func autorisationAccordée() async -> Bool { true }
    func planifierRappels(objectifML: Int, consomméML: Int) async {}
    func programmerRappelPostSéance() async {}
    func programmerSnooze() async {}
    func annulerTout() async {}
    func désactiverPourLaJournée() async {}
}

struct MockStoreService: StoreServicing {
    var statut: EntitlementStatus = .free
    func currentStatus() async -> EntitlementStatus { statut }
    func produitPlus() async -> StoreProduct? {
        StoreProduct(displayName: "Wello+", displayPrice: "8,99 €")
    }
    func acheter() async throws -> PurchaseOutcome { .success }
    func restaurer() async -> EntitlementStatus { statut }
    func observerTransactions() -> AsyncStream<EntitlementStatus> {
        AsyncStream { $0.finish() }
    }
}
