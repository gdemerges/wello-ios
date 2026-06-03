import Foundation
import HealthKit

/// Implémentation réelle de l'accès HealthKit. Dégrade gracieusement (retours neutres)
/// si HealthKit est indisponible ou l'autorisation refusée.
///
/// `@unchecked Sendable` : `HKHealthStore` n'est pas formellement `Sendable` mais est
/// thread-safe et utilisé sans état mutable partagé ici.
final class HealthKitService: HealthKitServicing, @unchecked Sendable {
    private let store = HKHealthStore()

    private let workoutType = HKObjectType.workoutType()
    private let bodyMassType = HKQuantityType(.bodyMass)
    private let waterType = HKQuantityType(.dietaryWater)

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        // Eau aussi en lecture : nécessaire pour requêter puis supprimer nos échantillons.
        let read: Set<HKObjectType> = [workoutType, bodyMassType, waterType]
        let write: Set<HKSampleType> = [waterType]
        try? await store.requestAuthorization(toShare: write, read: read)
    }

    func minutesEffortDuJour() async -> Int {
        let début = Calendar.current.startOfDay(for: .now)
        return await minutesEffortDepuis(début)
    }

    func minutesEffortDepuis(_ date: Date) async -> Int {
        guard HKHealthStore.isHealthDataAvailable() else { return 0 }
        let prédicat = HKQuery.predicateForSamples(withStart: date, end: .now)
        let workouts: [HKWorkout] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: workoutType, predicate: prédicat,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                cont.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(q)
        }
        let secondes = workouts.reduce(0) { $0 + $1.duration }
        return Int(secondes / 60)
    }

    func dernierWorkoutTerminé() async -> Date? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        let tri = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let workout: HKWorkout? = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: workoutType, predicate: nil,
                                  limit: 1, sortDescriptors: [tri]) { _, samples, _ in
                cont.resume(returning: samples?.first as? HKWorkout)
            }
            store.execute(q)
        }
        return workout?.endDate
    }

    func dernierPoids() async -> Double? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        let tri = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let sample: HKQuantitySample? = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: bodyMassType, predicate: nil,
                                  limit: 1, sortDescriptors: [tri]) { _, samples, _ in
                cont.resume(returning: samples?.first as? HKQuantitySample)
            }
            store.execute(q)
        }
        return sample?.quantity.doubleValue(for: .gramUnit(with: .kilo))
    }

    func écrireEau(ml: Int, date: Date) async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let quantité = HKQuantity(unit: .literUnit(with: .milli), doubleValue: Double(ml))
        let sample = HKQuantitySample(type: waterType, quantity: quantité, start: date, end: date)
        try? await store.save(sample)
    }

    func supprimerEau(ml: Int, date: Date) async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        // Fenêtre étroite autour de l'instant d'écriture (start == end == date).
        let prédicat = HKQuery.predicateForSamples(withStart: date.addingTimeInterval(-1),
                                                   end: date.addingTimeInterval(1))
        let échantillons: [HKQuantitySample] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: waterType, predicate: prédicat,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                cont.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            store.execute(q)
        }
        // On ne supprime que l'échantillon du bon montant (celui de cette prise).
        let cible = échantillons.first { Int($0.quantity.doubleValue(for: .literUnit(with: .milli)).rounded()) == ml }
        if let cible { try? await store.delete(cible) }
    }

    func prisesEauExternes(depuis date: Date) async -> [PriseEauExterne] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        let prédicat = HKQuery.predicateForSamples(withStart: date, end: .now)
        let échantillons: [HKQuantitySample] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: waterType, predicate: prédicat,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                cont.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            store.execute(q)
        }
        // On exclut nos propres échantillons (déjà comptés via les HydrationLog "app").
        let nous = HKSource.default()
        return échantillons
            .filter { $0.sourceRevision.source != nous }
            .map { PriseEauExterne(id: $0.uuid,
                                   ml: Int($0.quantity.doubleValue(for: .literUnit(with: .milli)).rounded()),
                                   date: $0.startDate) }
    }
}
