import Foundation
import HealthKit

/// Lecture HealthKit minimale côté Watch : énergie active du jour (pour le recalcul autonome de
/// l'objectif). Dégrade à 0 si indisponible/refusé. L'écriture de l'eau reste côté iPhone.
final class HealthKitWatchService: @unchecked Sendable {
    private let store = HKHealthStore()
    private let energyType = HKQuantityType(.activeEnergyBurned)

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        try? await store.requestAuthorization(toShare: [], read: [energyType])
    }

    /// Énergie active brûlée aujourd'hui (kcal). 0 si indisponible/refusé.
    func énergieActiveDuJour() async -> Double {
        guard HKHealthStore.isHealthDataAvailable() else { return 0 }
        let début = Calendar.current.startOfDay(for: .now)
        let prédicat = HKQuery.predicateForSamples(withStart: début, end: .now)
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: energyType, quantitySamplePredicate: prédicat,
                                      options: .cumulativeSum) { _, stats, _ in
                cont.resume(returning: stats?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0)
            }
            store.execute(q)
        }
    }
}
