import Foundation
import SwiftData
import WelloKit

/// Signaux « effectifs » des services, pour le diagnostic affiché au Profil :
/// non pas le statut d'autorisation brut (HealthKit masque le statut de lecture),
/// mais ce qui a réellement fonctionné au dernier rafraîchissement.
struct ÉtatServices: Sendable {
    var poidsDepuisSanté = false
    var localisationDisponible = false
    var météoDisponible = false
    var notificationsAutorisées = false
}

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
    /// État effectif des services, rafraîchi à chaque `refreshToday()`.
    private(set) var étatServices = ÉtatServices()
    /// Cache météo du jour (≤ 30 min) pour limiter les appels Open-Meteo.
    private var météoCache: (snapshot: WeatherSnapshot, capturéeÀ: Date)?

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

        let (snapshot, localisationOK) = await météoActuelle()
        météoIndisponible = (snapshot == nil)

        let inputs = CalculatorInputs(weightKg: poids, effortMinutes: effort,
                                      weather: snapshot, medicalFloorML: profil.medicalFloorML)
        let resultat = calculator.calculate(inputs)
        breakdown = resultat
        upsertDailyGoal(resultat)

        await importerEauHealthKit()

        let notifsOK = await notifications.autorisationAccordée()
        étatServices = ÉtatServices(poidsDepuisSanté: poidsHK != nil,
                                    localisationDisponible: localisationOK,
                                    météoDisponible: snapshot != nil,
                                    notificationsAutorisées: notifsOK)

        if profil.remindersEnabled {
            _ = await notifications.requestAuthorization()
            await notifications.planifierRappels(objectifML: resultat.totalML, consomméML: consomméAujourdhui())
            await détecterPostSéance()
        }
    }

    /// Météo du jour avec cache (≤ 30 min, même jour) pour limiter les appels réseau.
    private func météoActuelle() async -> (snapshot: WeatherSnapshot?, localisationOK: Bool) {
        if let cache = météoCache,
           Date.now.timeIntervalSince(cache.capturéeÀ) < 1800,
           Calendar.current.isDate(cache.capturéeÀ, inSameDayAs: .now) {
            return (cache.snapshot, true)
        }
        guard let coords = await location.coordonnéesActuelles() else { return (nil, false) }
        let snapshot = await weather.météoDuJour(latitude: coords.latitude, longitude: coords.longitude)
        if let snapshot { météoCache = (snapshot, .now) }
        return (snapshot, true)
    }

    /// Importe les prises d'eau saisies hors Wello (Watch, autres apps) en HydrationLog,
    /// dédupliquées par UUID HealthKit. SwiftData reste l'unique source de vérité du consommé.
    private func importerEauHealthKit() async {
        let début = Calendar.current.startOfDay(for: .now)
        let externes = await healthKit.prisesEauExternes(depuis: début)
        guard !externes.isEmpty else { return }

        let descripteur = FetchDescriptor<HydrationLog>(predicate: #Predicate { $0.healthKitUUID != nil })
        let déjàImportés = Set((try? modelContext.fetch(descripteur))?.compactMap(\.healthKitUUID) ?? [])

        for prise in externes where !déjàImportés.contains(prise.id) {
            modelContext.insert(HydrationLog(amountML: prise.ml, loggedAt: prise.date,
                                             source: "healthkit", healthKitUUID: prise.id))
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

    /// Annule la prise d'eau la plus récente du jour : retire le HydrationLog (la jauge baisse)
    /// et supprime l'échantillon correspondant dans Santé.app. No-op s'il n'y a aucune prise.
    func annulerDernièrePrise() async {
        let début = Calendar.current.startOfDay(for: .now)
        var descripteur = FetchDescriptor<HydrationLog>(
            predicate: #Predicate { $0.loggedAt >= début },
            sortBy: [SortDescriptor(\.loggedAt, order: .reverse)]
        )
        descripteur.fetchLimit = 1
        guard let dernière = try? modelContext.fetch(descripteur).first else { return }

        let ml = dernière.amountML
        let date = dernière.loggedAt
        modelContext.delete(dernière)
        await healthKit.supprimerEau(ml: ml, date: date)

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
