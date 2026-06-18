import Foundation
import SwiftData
import WelloKit
import WidgetKit

/// Signaux « effectifs » des services, pour le diagnostic affiché au Profil :
/// non pas le statut d'autorisation brut (HealthKit masque le statut de lecture),
/// mais ce qui a réellement fonctionné au dernier rafraîchissement.
struct ÉtatServices: Sendable {
    var localisationDisponible = false
    var météoDisponible = false
    var notificationsAutorisées = false

    /// Tout fonctionne : on masque alors le diagnostic.
    var tousOK: Bool { météoDisponible && notificationsAutorisées }
}

/// Mode courant des rappels, pour le sous-titre du Profil.
enum ModeRappels: Sendable, Equatable { case fixe, apprentissage, adaptatif }

/// État des rappels exposé à l'UI (mode + fenêtre détectée si adaptatif).
struct ÉtatRappels: Sendable, Equatable {
    var mode: ModeRappels = .fixe
    var fenêtre: FenêtreÉveil?
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
    private let planner = AdaptiveReminderPlanner()
    /// Lit le palier au moment de planifier (injecté pour découpler le store de l'EntitlementStore).
    private let rappelsAdaptatifsDébloqués: @MainActor () -> Bool

    /// Objectif détaillé du jour, recalculé par `refreshToday()`.
    private(set) var breakdown: GoalBreakdown?
    /// Vrai si la météo n'a pas pu être récupérée (réseau/localisation) — distinct d'un bonus à 0.
    private(set) var météoIndisponible = false
    /// État effectif des services, rafraîchi à chaque `refreshToday()`.
    private(set) var étatServices = ÉtatServices()
    /// Mode courant des rappels (lu par le Profil). Mis à jour à chaque replanification.
    private(set) var étatRappels = ÉtatRappels()
    /// Cache météo du jour (≤ 30 min) en mémoire ; doublé d'un cache persistant (UserDefaults).
    private var météoCache: (snapshot: WeatherSnapshot, capturéeÀ: Date)?
    /// Dernier recalcul réussi : sert à throttler les rafraîchissements redondants.
    private var dernierRefresh: Date?
    /// L'autorisation HealthKit n'est demandée qu'une fois par session.
    private var autorisationDemandée = false

    private enum Clés {
        static let météoRessentie = "wello.meteo.ressentieC"
        static let météoDate = "wello.meteo.capturéeA"
    }

    /// Fenêtre de throttle du recalcul et de validité du cache météo.
    private static let fenêtreRefresh: TimeInterval = 600    // 10 min
    private static let fenêtreMétéo: TimeInterval = 1800     // 30 min

    init(modelContext: ModelContext,
         healthKit: HealthKitServicing,
         weather: WeatherServicing,
         location: LocationServicing,
         notifications: NotificationServicing,
         rappelsAdaptatifsDébloqués: @escaping @MainActor () -> Bool = { false }) {
        self.modelContext = modelContext
        self.healthKit = healthKit
        self.weather = weather
        self.location = location
        self.notifications = notifications
        self.rappelsAdaptatifsDébloqués = rappelsAdaptatifsDébloqués
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

    /// Recalcule l'objectif du jour à partir du sexe (base EFSA), de l'énergie active et de la
    /// météo (best-effort), puis met à jour (upsert) le DailyGoal du jour. Replanifie les rappels.
    /// Throttlé (10 min, même jour) ; `force` court-circuite. Si le sexe n'est pas renseigné,
    /// aucun objectif n'est calculé (choix forcé à l'onboarding).
    func refreshToday(force: Bool = false) async {
        if !force, let dernier = dernierRefresh,
           Date.now.timeIntervalSince(dernier) < Self.fenêtreRefresh,
           Calendar.current.isDate(dernier, inSameDayAs: .now) {
            return
        }

        let profil = profilCourant()
        guard let sexe = profil.sexe else {
            breakdown = nil   // pas d'objectif tant que le sexe n'est pas renseigné
            return
        }
        dernierRefresh = .now

        // Demande d'autorisation HealthKit une seule fois par session (inutile ensuite).
        if !autorisationDemandée {
            await healthKit.requestAuthorization()
            autorisationDemandée = true
        }
        let énergie = await healthKit.énergieActiveDuJour()

        let (snapshot, localisationOK) = await météoActuelle()
        météoIndisponible = (snapshot == nil)

        let inputs = CalculatorInputs(sex: sexe, activeEnergyKcal: énergie, weather: snapshot,
                                      physiologicalState: profil.etatPhysio,
                                      renalBonusML: profil.renalBonusEffectifML,
                                      tuning: profil.tuning)
        let resultat = calculator.calculate(inputs)
        breakdown = resultat
        upsertDailyGoal(resultat)
        rechargerWidgets()

        await importerEauHealthKit()

        let notifsOK = await notifications.autorisationAccordée()
        étatServices = ÉtatServices(localisationDisponible: localisationOK,
                                    météoDisponible: snapshot != nil,
                                    notificationsAutorisées: notifsOK)

        if profil.remindersEnabled {
            _ = await notifications.requestAuthorization()
            await planifierSelonPalier(objectifML: resultat.totalML)
            await détecterPostSéance()
        }
    }

    /// Météo du jour avec cache (≤ 30 min, même jour) en mémoire ET persistant : évite un fix GPS
    /// + un appel réseau même au démarrage à froid si on a relevé la météo récemment.
    private func météoActuelle() async -> (snapshot: WeatherSnapshot?, localisationOK: Bool) {
        if let snap = météoCachéeValide() { return (snap, true) }
        guard let coords = await location.coordonnéesActuelles() else { return (nil, false) }
        let snapshot = await weather.météoDuJour(latitude: coords.latitude, longitude: coords.longitude)
        if let snapshot { mémoriserMétéo(snapshot) }
        return (snapshot, true)
    }

    /// Cache météo valide (mémoire en priorité, puis UserDefaults), ou nil si périmé/absent.
    private func météoCachéeValide() -> WeatherSnapshot? {
        if let cache = météoCache, météoFraîche(cache.capturéeÀ) { return cache.snapshot }
        let d = UserDefaults.standard
        if let capturée = d.object(forKey: Clés.météoDate) as? Date, météoFraîche(capturée) {
            let snap = WeatherSnapshot(apparentTemperatureC: d.double(forKey: Clés.météoRessentie))
            météoCache = (snap, capturée)   // réhydrate le cache mémoire
            return snap
        }
        return nil
    }

    private func météoFraîche(_ date: Date) -> Bool {
        Date.now.timeIntervalSince(date) < Self.fenêtreMétéo
            && Calendar.current.isDate(date, inSameDayAs: .now)
    }

    private func mémoriserMétéo(_ snap: WeatherSnapshot) {
        let maintenant = Date.now
        météoCache = (snap, maintenant)
        let d = UserDefaults.standard
        d.set(snap.apparentTemperatureC, forKey: Clés.météoRessentie)
        d.set(maintenant, forKey: Clés.météoDate)
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

    /// Enregistre une prise (eau ou autre boisson) : SwiftData (source de vérité) + écriture
    /// HealthKit de l'hydratation effective positive (une boisson à effectif ≤ 0 n'écrit rien).
    func log(ml: Int, drink: DrinkType = .water, coefficient: Double = 1.0) async {
        let entrée = HydrationLog(amountML: ml, loggedAt: .now, source: "app",
                                  drinkType: drink.rawValue, coefficient: coefficient)
        modelContext.insert(entrée)
        let effectif = max(0, entrée.effectiveML)
        if effectif > 0 { await healthKit.écrireEau(ml: effectif, date: entrée.loggedAt) }

        if let objectif = breakdown?.totalML {
            await planifierSelonPalier(objectifML: objectif)
        }
        rechargerWidgets()
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

        let effectif = max(0, dernière.effectiveML)
        let date = dernière.loggedAt
        modelContext.delete(dernière)
        if effectif > 0 { await healthKit.supprimerEau(ml: effectif, date: date) }

        if let objectif = breakdown?.totalML {
            await planifierSelonPalier(objectifML: objectif)
        }
        rechargerWidgets()
    }

    /// Supprime une prise précise (depuis le détail d'un jour) : SwiftData + Santé (si saisie
    /// dans Wello) + replanification des rappels.
    func supprimer(_ log: HydrationLog) async {
        let effectif = max(0, log.effectiveML)
        let date = log.loggedAt
        let estApp = log.source == "app"
        modelContext.delete(log)
        if estApp && effectif > 0 { await healthKit.supprimerEau(ml: effectif, date: date) }
        if let objectif = breakdown?.totalML {
            await planifierSelonPalier(objectifML: objectif)
        }
        rechargerWidgets()
    }

    /// Replanifie les rappels selon le palier : `plus` (avec assez de données) → adaptatif ;
    /// sinon (gratuit ou cold-start) → rappels fixes existants. No-op si rappels désactivés.
    private func planifierSelonPalier(objectifML: Int) async {
        guard profilCourant().remindersEnabled else { return }
        let consommé = consomméAujourdhui()
        let objectifAtteint = consommé >= objectifML

        if rappelsAdaptatifsDébloqués() {
            let historique = historiquePrises()
            if planner.aAssezDeDonnées(historique) {
                let fenêtre = await fenêtreÉveilCourante(historique: historique)
                let heures = planner.planRappels(historique: historique, fenêtre: fenêtre,
                                                 now: .now, objectifAtteint: objectifAtteint)
                étatRappels = ÉtatRappels(mode: .adaptatif, fenêtre: fenêtre)
                await notifications.planifierRappelsAdaptatifs(auxHeures: heures)
                return
            }
            étatRappels = ÉtatRappels(mode: .apprentissage, fenêtre: nil)
        } else {
            étatRappels = ÉtatRappels(mode: .fixe, fenêtre: nil)
        }
        await notifications.planifierRappels(objectifML: objectifML, consomméML: consommé)
    }

    /// Prises des `joursHistoire` jours précédents (today exclu), groupées par jour en
    /// minutes depuis minuit. Sert d'apprentissage des trous habituels.
    private func historiquePrises() -> [JourDePrises] {
        let cal = Calendar.current
        let finExclue = cal.startOfDay(for: .now)
        guard let début = cal.date(byAdding: .day, value: -AdaptiveReminderPlanner.joursHistoire, to: finExclue)
        else { return [] }
        let descripteur = FetchDescriptor<HydrationLog>(
            predicate: #Predicate { $0.loggedAt >= début && $0.loggedAt < finExclue }
        )
        let logs = (try? modelContext.fetch(descripteur)) ?? []
        let parJour = Dictionary(grouping: logs) { cal.startOfDay(for: $0.loggedAt) }
        return parJour.values.map { duJour in
            JourDePrises(minutesDePrise: duJour.map {
                let c = cal.dateComponents([.hour, .minute], from: $0.loggedAt)
                return (c.hour ?? 0) * 60 + (c.minute ?? 0)
            })
        }
    }

    /// Fenêtre d'éveil : sommeil HealthKit → historique → défaut.
    private func fenêtreÉveilCourante(historique: [JourDePrises]) async -> FenêtreÉveil {
        let cal = Calendar.current
        let début = cal.date(byAdding: .day, value: -AdaptiveReminderPlanner.joursHistoire, to: .now) ?? .now
        let périodes = await healthKit.périodesSommeil(depuis: début)
        if let f = planner.fenêtreDepuisSommeil(périodes) { return f }
        if let f = planner.fenêtreDepuisHistorique(historique) { return f }
        return .défaut
    }

    /// Somme des prises d'eau du jour (toutes sources).
    func consomméAujourdhui() -> Int {
        let début = Calendar.current.startOfDay(for: .now)
        let descripteur = FetchDescriptor<HydrationLog>(
            predicate: #Predicate { $0.loggedAt >= début }
        )
        let logs = (try? modelContext.fetch(descripteur)) ?? []
        return clampedDayTotal(logs.reduce(0) { $0 + $1.effectiveML })
    }

    /// Recharge toutes les timelines de widget : à appeler après tout changement du consommé
    /// ou de l'objectif du jour.
    private func rechargerWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func upsertDailyGoal(_ r: GoalBreakdown) {
        let jour = Calendar.current.startOfDay(for: .now)
        let descripteur = FetchDescriptor<DailyGoal>(predicate: #Predicate { $0.date == jour })

        if let goal = try? modelContext.fetch(descripteur).first {
            goal.baseML = r.baseML
            goal.activityBonusML = r.activityBonusML
            goal.weatherBonusML = r.weatherBonusML
            goal.lifeStageBonusML = r.lifeStageBonusML
            goal.renalBonusML = r.renalBonusML
            goal.manualAdjustmentML = r.manualAdjustmentML
            goal.totalML = r.totalML
            goal.calculatedAt = .now
        } else {
            let goal = DailyGoal(date: jour, baseML: r.baseML, activityBonusML: r.activityBonusML,
                                 weatherBonusML: r.weatherBonusML,
                                 lifeStageBonusML: r.lifeStageBonusML, renalBonusML: r.renalBonusML,
                                 manualAdjustmentML: r.manualAdjustmentML,
                                 totalML: r.totalML)
            modelContext.insert(goal)
        }
    }
}
