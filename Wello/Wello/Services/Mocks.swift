import Foundation
import WelloKit

/// Implémentations factices pour les SwiftUI previews et le développement hors device.
struct MockHealthKitService: HealthKitServicing {
    var énergieKcal: Double = 320
    func requestAuthorization() async {}
    func énergieActiveDuJour() async -> Double { énergieKcal }
    func écrireEau(ml: Int, date: Date) async -> UUID? { nil }
    func supprimerEau(uuid: UUID?, ml: Int, date: Date) async {}
    func prisesEauExternes(depuis date: Date) async -> [PriseEauExterne] { [] }
    func dernierWorkoutTerminé() async -> Date? { nil }
    var périodesSommeilMock: [PériodeSommeil] = []
    func périodesSommeil(depuis date: Date) async -> [PériodeSommeil] { périodesSommeilMock }
    func supprimerToutesNosPrisesEau() async {}
    func observerEnArrièrePlan(_ surChangement: @escaping @Sendable () async -> Void) {}
}

struct MockWeatherService: WeatherServicing {
    var snapshot: WeatherSnapshot? = WeatherSnapshot(apparentTemperatureC: 33)
    func météoDuJour(latitude: Double, longitude: Double) async -> WeatherSnapshot? { snapshot }
}

struct MockLocationService: LocationServicing {
    var coords: (latitude: Double, longitude: Double)? = (48.85, 2.35)
    func coordonnéesActuelles() async -> (latitude: Double, longitude: Double)? { coords }
}

/// Mock du pont Watch : ne fait rien (previews, tests, appareils sans Watch).
struct MockWatchSync: WatchSyncing {
    func pousser(_ snapshot: WatchSyncSnapshot) {}
}

struct MockNotificationService: NotificationServicing {
    func requestAuthorization() async -> Bool { true }
    func autorisationAccordée() async -> Bool { true }
    func planifierRappels(objectifML: Int, consomméML: Int) async {}
    func planifierRappelsAdaptatifs(auxHeures heures: [Date], objectifML: Int,
                                    consomméML: Int, fenêtre: FenêtreÉveil) async {}
    func programmerBilanHebdomadaire() async {}
    func programmerRappelPostSéance() async {}
    func programmerSnooze() async {}
    func annulerTout() async {}
    func désactiverPourLaJournée() async {}
}

struct MockStoreService: StoreServicing {
    var statut: EntitlementStatus = .free
    func statutActuel() async -> EntitlementStatus { statut }
    func produits() async -> [StoreProduct] {
        [StoreProduct(id: StoreIDs.plusAnnual, kind: .annual, displayName: "Wello+ annuel",
                      displayPrice: "4,99 €", offreIntro: "Essai gratuit : 1 semaine"),
         StoreProduct(id: StoreIDs.plusLifetime, kind: .lifetime, displayName: "Wello+ à vie",
                      displayPrice: "12,99 €", offreIntro: nil)]
    }
    func acheter(_ productID: String) async throws -> PurchaseOutcome { .success }
    func restaurer() async -> EntitlementStatus { statut }
    func observerTransactions() -> AsyncStream<EntitlementStatus> {
        AsyncStream { $0.finish() }
    }
}
