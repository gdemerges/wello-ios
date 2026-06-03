import Foundation
import SwiftData
import WelloKit

/// Orchestrateur central : calcule/rafraîchit l'objectif du jour et enregistre les prises d'eau.
/// Injecté dans l'environnement SwiftUI. Source de vérité du « consommé » = somme des HydrationLog.
@MainActor
@Observable
final class HydrationStore {
    private let modelContext: ModelContext
    private let healthKit: HealthKitServicing
    private let weather: WeatherServicing
    private let location: LocationServicing
    private let notifications: NotificationServicing
    private let calculator = HydrationCalculator()

    /// Objectif détaillé du jour, recalculé par `refreshToday()`.
    private(set) var breakdown: GoalBreakdown?
    /// Vrai si la météo n'a pas pu être récupérée (réseau/localisation) — distinct d'un bonus à 0.
    private(set) var météoIndisponible = false

    init(modelContext: ModelContext,
         healthKit: HealthKitServicing,
         weather: WeatherServicing,
         location: LocationServicing,
         notifications: NotificationServicing) {
        self.modelContext = modelContext
        self.healthKit = healthKit
        self.weather = weather
        self.location = location
        self.notifications = notifications
    }

    /// Récupère ou crée l'unique profil utilisateur.
    func profilCourant() -> UserProfile {
        let descripteur = FetchDescriptor<UserProfile>()
        if let existant = try? modelContext.fetch(descripteur).first {
            return existant
        }
        let nouveau = UserProfile()
        modelContext.insert(nouveau)
        return nouveau
    }

    /// Recalcule l'objectif du jour à partir du poids, de l'effort et de la météo (best-effort),
    /// puis met à jour (upsert) le DailyGoal du jour. Replanifie les rappels.
    func refreshToday() async {
        let profil = profilCourant()

        await healthKit.requestAuthorization()
        let effort = await healthKit.minutesEffortDuJour()
        let poidsHK = await healthKit.dernierPoids()
        let poids = résoudrePoids(healthKitKg: poidsHK, profilKg: profil.weightKg)

        var snapshot: WeatherSnapshot? = nil
        if let coords = await location.coordonnéesActuelles() {
            snapshot = await weather.météoDuJour(latitude: coords.latitude, longitude: coords.longitude)
        }
        météoIndisponible = (snapshot == nil)

        let inputs = CalculatorInputs(weightKg: poids, effortMinutes: effort,
                                      weather: snapshot, medicalFloorML: profil.medicalFloorML)
        let resultat = calculator.calculate(inputs)
        breakdown = resultat
        upsertDailyGoal(resultat)

        if profil.remindersEnabled {
            _ = await notifications.requestAuthorization()
            await notifications.planifierRappels(objectifML: resultat.totalML, consomméML: consomméAujourdhui())
            await détecterPostSéance()
        }
    }

    /// Détecte un workout fraîchement terminé (< 1h) et déclenche un rappel post-séance,
    /// sans re-notifier deux fois la même séance (dédup via UserDefaults).
    private func détecterPostSéance() async {
        guard let fin = await healthKit.dernierWorkoutTerminé() else { return }
        guard fin > Date.now.addingTimeInterval(-3600) else { return }   // terminé dans la dernière heure

        let clé = "wello.dernierPostSéance"
        if let déjàNotifié = UserDefaults.standard.object(forKey: clé) as? Date, déjàNotifié >= fin {
            return
        }
        await notifications.programmerRappelPostSéance()
        UserDefaults.standard.set(fin, forKey: clé)
    }

    /// Action « Plus tard » : reprogramme un rappel dans 1h.
    func snoozerRappels() async {
        await notifications.programmerSnooze()
    }

    /// Coupe tous les rappels jusqu'à demain (reprogrammés au prochain refresh).
    func couperRappelsAujourdhui() async {
        await notifications.désactiverPourLaJournée()
    }

    /// Enregistre une prise d'eau : SwiftData (source de vérité) + écriture HealthKit (Santé.app).
    func log(ml: Int) async {
        let entrée = HydrationLog(amountML: ml, loggedAt: .now, source: "app")
        modelContext.insert(entrée)
        await healthKit.écrireEau(ml: ml, date: .now)

        if let objectif = breakdown?.totalML {
            await notifications.planifierRappels(objectifML: objectif, consomméML: consomméAujourdhui())
        }
    }

    /// Somme des prises d'eau du jour (toutes sources).
    func consomméAujourdhui() -> Int {
        let début = Calendar.current.startOfDay(for: .now)
        let descripteur = FetchDescriptor<HydrationLog>(
            predicate: #Predicate { $0.loggedAt >= début }
        )
        let logs = (try? modelContext.fetch(descripteur)) ?? []
        return logs.reduce(0) { $0 + $1.amountML }
    }

    private func upsertDailyGoal(_ r: GoalBreakdown) {
        let jour = Calendar.current.startOfDay(for: .now)
        let descripteur = FetchDescriptor<DailyGoal>(predicate: #Predicate { $0.date == jour })

        if let goal = try? modelContext.fetch(descripteur).first {
            goal.baseML = r.baseML
            goal.activityBonusML = r.activityBonusML
            goal.weatherBonusML = r.weatherBonusML
            goal.medicalFloorML = r.medicalFloorML
            goal.totalML = r.totalML
            goal.calculatedAt = .now
        } else {
            let goal = DailyGoal(date: jour, baseML: r.baseML, activityBonusML: r.activityBonusML,
                                 weatherBonusML: r.weatherBonusML, medicalFloorML: r.medicalFloorML,
                                 totalML: r.totalML)
            modelContext.insert(goal)
        }
    }
}
