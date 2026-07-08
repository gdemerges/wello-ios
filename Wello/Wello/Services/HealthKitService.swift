import Foundation
import HealthKit
import WelloKit

/// Implémentation réelle de l'accès HealthKit. Dégrade gracieusement (retours neutres)
/// si HealthKit est indisponible ou l'autorisation refusée.
///
/// `@unchecked Sendable` : `HKHealthStore` n'est pas formellement `Sendable` mais est
/// thread-safe et utilisé sans état mutable partagé ici.
final class HealthKitService: HealthKitServicing, @unchecked Sendable {
    private let store = HKHealthStore()

    private let workoutType = HKObjectType.workoutType()
    private let waterType = HKQuantityType(.dietaryWater)
    private let energyType = HKQuantityType(.activeEnergyBurned)
    private let sleepType = HKCategoryType(.sleepAnalysis)

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        // Eau aussi en lecture (requête/suppression de nos échantillons) ; énergie active
        // pour estimer la perte sudorale à l'effort.
        let read: Set<HKObjectType> = [workoutType, waterType, energyType, sleepType]
        let write: Set<HKSampleType> = [waterType]
        try? await store.requestAuthorization(toShare: write, read: read)
    }

    func énergieActiveDuJour() async -> Double {
        guard HKHealthStore.isHealthDataAvailable() else { return 0 }
        let début = Calendar.current.startOfDay(for: .now)
        let prédicat = HKQuery.predicateForSamples(withStart: début, end: .now)
        let workouts: [HKWorkout] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: workoutType, predicate: prédicat,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                cont.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(q)
        }
        // Énergie active de chaque séance ; à défaut (séance sans énergie enregistrée),
        // estimation depuis la durée à intensité modérée (~7 kcal/min).
        return workouts.reduce(0.0) { somme, w in
            if let kcal = w.statistics(for: energyType)?.sumQuantity()?.doubleValue(for: .kilocalorie()) {
                return somme + kcal
            }
            return somme + (w.duration / 60.0) * 7.0
        }
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

    func périodesSommeil(depuis date: Date) async -> [PériodeSommeil] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        let prédicat = HKQuery.predicateForSamples(withStart: date, end: .now)
        let samples: [HKCategorySample] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: sleepType, predicate: prédicat,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                cont.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            store.execute(q)
        }
        let asleep: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue
        ]
        return samples
            .filter { asleep.contains($0.value) }
            .map { PériodeSommeil(début: $0.startDate, fin: $0.endDate) }
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
        // Comparaison par bundle identifier plutôt que HKSource.default() : cet appel peut
        // lever une NSException (non interceptable en Swift) hors contexte pleinement
        // entitled, notamment en Simulateur — crash reproduit lors du premier refreshToday().
        let notreBundleID = Bundle.main.bundleIdentifier
        return échantillons
            .filter { $0.sourceRevision.source.bundleIdentifier != notreBundleID }
            .map { PriseEauExterne(id: $0.uuid,
                                   ml: Int($0.quantity.doubleValue(for: .literUnit(with: .milli)).rounded()),
                                   date: $0.startDate) }
    }
}
