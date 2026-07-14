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
    private let alcoholType = HKQuantityType(.numberOfAlcoholicBeverages)
    private let energyType = HKQuantityType(.activeEnergyBurned)
    private let sleepType = HKCategoryType(.sleepAnalysis)

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        // Eau aussi en lecture (requête/suppression de nos échantillons) ; énergie active
        // pour estimer la perte sudorale à l'effort.
        let read: Set<HKObjectType> = [workoutType, waterType, alcoholType, energyType, sleepType]
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

    /// Livraison en arrière-plan (entitlement HealthKit « Background Delivery ») + observation :
    /// une séance terminée ou une prise d'eau saisie ailleurs réveille l'app, même fermée. Sans
    /// ça, objectif, rappels, widget et Live Activity restaient figés jusqu'à la réouverture.
    ///
    /// Le `completionHandler` de l'observateur DOIT être appelé une fois le travail fini : sinon
    /// HealthKit ralentit puis coupe la livraison pour l'app.
    func observerEnArrièrePlan(_ surChangement: @escaping @Sendable () async -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        // Séances : alimentent le bonus d'activité et le rappel post-séance.
        // Eau/alcool : prises saisies dans une autre app ou au poignet, à importer.
        for type: HKSampleType in [workoutType, waterType, alcoholType] {
            store.enableBackgroundDelivery(for: type, frequency: .hourly) { _, _ in
                // Best-effort : un refus (autorisation, entitlement absent) laisse simplement
                // l'app fonctionner comme avant, au premier plan.
            }
            let observateur = HKObserverQuery(sampleType: type, predicate: nil) { _, acquitter, _ in
                Task {
                    await surChangement()
                    acquitter()
                }
            }
            store.execute(observateur)
        }
    }

    func écrireEau(ml: Int, date: Date) async -> UUID? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        let quantité = HKQuantity(unit: .literUnit(with: .milli), doubleValue: Double(ml))
        let sample = HKQuantitySample(type: waterType, quantity: quantité, start: date, end: date)
        do {
            try await store.save(sample)
            return sample.uuid
        } catch {
            return nil
        }
    }

    func supprimerEau(uuid: UUID?, ml: Int, date: Date) async {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        // Chemin précis : suppression par identité de l'échantillon.
        if let uuid {
            let prédicat = HKQuery.predicateForObject(with: uuid)
            let échantillons: [HKQuantitySample] = await withCheckedContinuation { cont in
                let q = HKSampleQuery(sampleType: waterType, predicate: prédicat,
                                      limit: 1, sortDescriptors: nil) { _, samples, _ in
                    cont.resume(returning: (samples as? [HKQuantitySample]) ?? [])
                }
                store.execute(q)
            }
            if let cible = échantillons.first { try? await store.delete(cible) }
            return
        }

        // Repli (prises écrites avant `healthSampleUUID`) : fenêtre étroite + montant exact.
        let prédicat = HKQuery.predicateForSamples(withStart: date.addingTimeInterval(-1),
                                                   end: date.addingTimeInterval(1))
        let échantillons: [HKQuantitySample] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: waterType, predicate: prédicat,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                cont.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            store.execute(q)
        }
        let cible = échantillons.first { Int($0.quantity.doubleValue(for: .literUnit(with: .milli)).rounded()) == ml }
        if let cible { try? await store.delete(cible) }
    }

    /// `deleteObjects` ne touche que les échantillons **écrits par cette app** : les prises
    /// enregistrées dans Santé par une autre source restent intactes, quoi qu'il arrive.
    func supprimerToutesNosPrisesEau() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let tout = HKQuery.predicateForSamples(withStart: .distantPast, end: .distantFuture)
        _ = try? await store.deleteObjects(of: waterType, predicate: tout)
    }

    func prisesEauExternes(depuis date: Date) async -> [PriseEauExterne] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        let eau = await échantillonsExternes(type: waterType, depuis: date)
            .map { PriseEauExterne(id: $0.uuid,
                                   ml: Int($0.quantity.doubleValue(for: .literUnit(with: .milli)).rounded()),
                                   date: $0.startDate,
                                   drink: .water,
                                   coefficient: 1.0) }

        // Santé expose l'alcool comme un nombre de boissons, pas un volume. On convertit
        // chaque boisson en 150 ml indicatifs pour alimenter l'historique et les stats Wello,
        // sans ajouter d'hydratation effective (coefficient générique alcool = 0).
        let alcool = await échantillonsExternes(type: alcoholType, depuis: date)
            .compactMap { sample -> PriseEauExterne? in
                let verres = sample.quantity.doubleValue(for: .count())
                guard verres > 0 else { return nil }
                return PriseEauExterne(id: sample.uuid,
                                       ml: Int((verres * 150).rounded()),
                                       date: sample.startDate,
                                       drink: .alcohol,
                                       coefficient: DrinkType.alcohol.defaultCoefficient)
            }

        return (eau + alcool).sorted { $0.date < $1.date }
    }

    private func échantillonsExternes(type: HKQuantityType, depuis date: Date) async -> [HKQuantitySample] {
        let prédicat = HKQuery.predicateForSamples(withStart: date, end: .now)
        let échantillons: [HKQuantitySample] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: prédicat,
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
    }
}
