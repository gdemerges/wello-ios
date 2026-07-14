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

/// Fraîcheur des données qui alimentent l'objectif et le consommé.
struct ÉtatSourcesHydratation: Sendable, Equatable {
    var objectifCalculéÀ: Date?
    var énergieLueÀ: Date?
    var météoCapturéeÀ: Date?
    var importsSantéLusÀ: Date?
    var importsSantéAjoutés: Int = 0
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
    private let watchSync: WatchSyncing
    private let calculator = HydrationCalculator()
    private let planner = AdaptiveReminderPlanner()
    /// Live Activity de progression du jour (écran verrouillé + Dynamic Island). Inerte si désactivée.
    private let liveActivity = LiveActivityManager()
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
    /// Fraîcheur des données affichée dans la carte de confiance de l'accueil.
    private(set) var étatSources = ÉtatSourcesHydratation()
    /// Vrai si l'utilisateur a coupé les rappels pour aujourd'hui (persisté : survit au relaunch
    /// et à tout nouveau log, contrairement à un simple `@State` de vue). Se réinitialise seul
    /// le lendemain (comparaison au jour courant, pas de nettoyage explicite nécessaire).
    private(set) var rappelsCoupésAujourdhui = false
    /// Série d'objectifs atteints en cours (aujourd'hui compris s'il est atteint). Mémoïsée ici
    /// plutôt que recalculée dans le `body` de l'accueil : sinon chaque évaluation rechargeait
    /// **tout** l'historique des prises pour en reconstruire le consommé jour par jour.
    private(set) var sérieCourante = 0
    /// Cache météo du jour (≤ 30 min) en mémoire ; doublé d'un cache persistant (UserDefaults).
    private var météoCache: (snapshot: WeatherSnapshot, capturéeÀ: Date)?
    /// Recalcul différé demandé par le Profil (un cran de stepper = un `refreshToday` complet
    /// sinon). Conservé pour annuler le précédent à chaque nouveau cran.
    private var tâcheRecalcul: Task<Void, Never>?
    /// Dernier recalcul réussi : sert à throttler les rafraîchissements redondants.
    private var dernierRefresh: Date?
    /// L'autorisation HealthKit n'est demandée qu'une fois par session.
    private var autorisationDemandée = false

    private enum Clés {
        static let météoRessentie = "wello.meteo.ressentieC"
        static let météoAltitude = "wello.meteo.altitudeM"
        static let météoDate = "wello.meteo.capturéeA"
        /// UUIDs d'imports externes supprimés (→ epoch), pour ne pas les réimporter le jour même.
        static let pierresTombales = "wello.import.pierresTombales"
        /// Date du jour où l'utilisateur a coupé les rappels via le bouton cloche de l'accueil.
        static let rappelsCoupésDate = "wello.rappels.coupesDate"
        /// Fin de la dernière séance déjà notifiée (dédup du rappel post-séance).
        static let dernierPostSéance = "wello.dernierPostSéance"
        /// Onboarding terminé (posé par `RootView` via `@AppStorage`).
        static let onboardingFait = "wello.hasOnboarded"

        /// Tout ce que l'app écrit sur l'appareil hors SwiftData — hors achats et préférences
        /// d'affichage, qui ne sont pas des données de suivi. Sert à la remise à zéro.
        static let toutesDonnéesDeSuivi = [météoRessentie, météoAltitude, météoDate,
                                           pierresTombales, rappelsCoupésDate, dernierPostSéance,
                                           onboardingFait]
    }

    /// Durée de vie d'une pierre tombale : au-delà, l'échantillon est hors de la fenêtre d'import
    /// journalière (`depuis: début`), donc plus aucun risque de réimport.
    private static let ttlPierreTombale: TimeInterval = 2 * 86400

    private var pierresTombalesBrutes: [String: Double] {
        (UserDefaults.standard.dictionary(forKey: Clés.pierresTombales) as? [String: Double]) ?? [:]
    }

    /// UUIDs d'imports externes récemment supprimés (purge/lecture pure, testée dans WelloKit).
    private var pierresTombales: Set<UUID> {
        PierresTombales.valides(pierresTombalesBrutes, maintenant: .now, ttl: Self.ttlPierreTombale)
    }

    /// Marque un UUID d'import externe comme supprimé (avec purge des entrées expirées).
    private func ajouterPierreTombale(_ uuid: UUID) {
        let màj = PierresTombales.enAjoutant(uuid, à: pierresTombalesBrutes,
                                             maintenant: .now, ttl: Self.ttlPierreTombale)
        UserDefaults.standard.set(màj, forKey: Clés.pierresTombales)
    }

    /// Fenêtre de throttle du recalcul et de validité du cache météo.
    private static let fenêtreRefresh: TimeInterval = 600    // 10 min
    private static let fenêtreMétéo: TimeInterval = 1800     // 30 min
    /// Délai de coalescence des réglages du Profil : le temps qu'un utilisateur qui maintient un
    /// stepper s'arrête, sans que l'objectif affiché paraisse en retard.
    private static let délaiRecalcul: Duration = .milliseconds(500)
    /// Horizon de calcul de la série (jours) : borne le fetch, une série plus longue relèverait
    /// de la fiction.
    private static let joursSérie = 400

    init(modelContext: ModelContext,
         healthKit: HealthKitServicing,
         weather: WeatherServicing,
         location: LocationServicing,
         notifications: NotificationServicing,
         watchSync: WatchSyncing = MockWatchSync(),
         rappelsAdaptatifsDébloqués: @escaping @MainActor () -> Bool = { false }) {
        self.modelContext = modelContext
        self.healthKit = healthKit
        self.weather = weather
        self.location = location
        self.notifications = notifications
        self.watchSync = watchSync
        self.rappelsAdaptatifsDébloqués = rappelsAdaptatifsDébloqués
        self.rappelsCoupésAujourdhui = Self.rappelsCoupésEncoreValide()
    }

    /// Vrai si une coupure « pour aujourd'hui » a été posée ce jour même (sinon périmée : un
    /// nouveau jour réactive tacitement les rappels sans action explicite de l'utilisateur).
    private static func rappelsCoupésEncoreValide() -> Bool {
        guard let date = UserDefaults.standard.object(forKey: Clés.rappelsCoupésDate) as? Date else { return false }
        return Calendar.current.isDateInToday(date)
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

    /// Recalcul demandé par un réglage du Profil (steppers, pickers, toggles). Coalescé : chaque
    /// nouveau cran annule le précédent, et un seul `refreshToday` part une fois la main levée —
    /// sans quoi chaque cran déclenchait lecture HealthKit, import des prises Santé et
    /// replanification des notifications.
    func demanderRecalcul() {
        tâcheRecalcul?.cancel()
        tâcheRecalcul = Task { [weak self] in
            try? await Task.sleep(for: Self.délaiRecalcul)
            guard !Task.isCancelled else { return }
            await self?.refreshToday(force: true)
        }
    }

    /// Recalcule l'objectif du jour à partir du sexe (base EFSA), de l'énergie active et de la
    /// météo (best-effort), puis met à jour (upsert) le DailyGoal du jour. Replanifie les rappels.
    /// Throttlé (10 min, même jour) ; `force` court-circuite. Si le sexe n'est pas renseigné,
    /// aucun objectif n'est calculé (choix forcé à l'onboarding).
    /// Branche l'observation HealthKit en arrière-plan : une séance terminée le soir relève
    /// l'objectif, replanifie les rappels et rafraîchit widget + Live Activity **sans attendre**
    /// que l'utilisateur rouvre l'app. À appeler une fois au démarrage.
    func démarrerObservationSanté() {
        healthKit.observerEnArrièrePlan { [weak self] in
            await self?.refreshToday(force: true, enArrièrePlan: true)
        }
    }

    func refreshToday(force: Bool = false, enArrièrePlan: Bool = false) async {
        if !force, let dernier = dernierRefresh,
           Date.now.timeIntervalSince(dernier) < Self.fenêtreRefresh,
           Calendar.current.isDate(dernier, inSameDayAs: .now) {
            return
        }

        // Réévalue la coupure « pour aujourd'hui » : périmée dès le changement de jour, même si
        // l'app est restée ouverte au passage de minuit sans action explicite de l'utilisateur.
        rappelsCoupésAujourdhui = Self.rappelsCoupésEncoreValide()

        let profil = profilCourant()
        guard let sexe = profil.sexe else {
            breakdown = nil   // pas d'objectif tant que le sexe n'est pas renseigné
            return
        }
        dernierRefresh = .now

        // Affichage immédiat : au démarrage à froid, `breakdown` est nil et les cartes (rythme,
        // détail, sources) restent masquées tant que HealthKit + GPS + météo n'ont pas répondu.
        // On amorce donc l'UI avec le dernier objectif du jour déjà persisté, avant tout `await` ;
        // le calcul complet ci-dessous l'affinera ensuite en douceur.
        if breakdown == nil { breakdown = objectifDuJourPersisté() }

        // Demande d'autorisation HealthKit une seule fois par session (inutile ensuite). Réveillé
        // en arrière-plan, on ne demande rien : aucune interface ne peut s'afficher, et une
        // observation qui se déclenche prouve que la lecture est déjà accordée.
        if !autorisationDemandée && !enArrièrePlan {
            await healthKit.requestAuthorization()
            autorisationDemandée = true
        }
        let énergie = await healthKit.énergieActiveDuJour()
        étatSources.énergieLueÀ = .now

        // En arrière-plan, on se contente de la météo en cache : un fix GPS hors premier plan
        // est lent, peu fiable, et ferait patienter le réveil HealthKit (qui doit être acquitté
        // vite). Un bonus météo légèrement daté vaut mieux qu'un réveil qui expire.
        let (snapshot, localisationOK, météoCapturéeÀ) = await météoActuelle(autoriserGPS: !enArrièrePlan)
        météoIndisponible = (snapshot == nil)
        étatSources.météoCapturéeÀ = météoCapturéeÀ

        let inputs = CalculatorInputs(sex: sexe, activeEnergyKcal: énergie, weather: snapshot,
                                      physiologicalState: profil.etatPhysio,
                                      renalBonusML: profil.renalBonusEffectifML,
                                      bodyWeightKg: profil.poidsPourCalcul,
                                      tuning: profil.tuning)
        let resultat = calculator.calculate(inputs)
        breakdown = resultat
        étatSources.objectifCalculéÀ = .now
        upsertDailyGoal(resultat)
        propagerChangement()

        let importsAjoutés = await importerEauHealthKit()
        étatSources.importsSantéLusÀ = .now
        étatSources.importsSantéAjoutés = importsAjoutés

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
    private func météoActuelle(autoriserGPS: Bool = true) async
        -> (snapshot: WeatherSnapshot?, localisationOK: Bool, capturéeÀ: Date?) {
        // Sans GPS (réveil en arrière-plan), on accepte la météo relevée plus tôt dans la journée
        // au lieu d'exiger 30 min de fraîcheur : sinon le recalcul perdrait le bonus météo et
        // **baisserait** l'objectif du jour — une régression pire que le bonus légèrement daté.
        if let cache = météoCachéeValide(fenêtre: autoriserGPS ? Self.fenêtreMétéo : nil) {
            return (cache.snapshot, true, cache.capturéeÀ)
        }
        guard autoriserGPS else { return (nil, false, nil) }
        guard let coords = await location.coordonnéesActuelles() else { return (nil, false, nil) }
        let snapshot = await weather.météoDuJour(latitude: coords.latitude, longitude: coords.longitude)
        if let snapshot {
            let capturéeÀ = mémoriserMétéo(snapshot)
            return (snapshot, true, capturéeÀ)
        }
        return (nil, true, nil)
    }

    /// Cache météo valide (mémoire en priorité, puis UserDefaults), ou nil si périmé/absent.
    /// `fenêtre` = âge maximal accepté ; `nil` = n'importe quel relevé du jour (arrière-plan).
    private func météoCachéeValide(fenêtre: TimeInterval?)
        -> (snapshot: WeatherSnapshot, capturéeÀ: Date)? {
        if let cache = météoCache, météoFraîche(cache.capturéeÀ, fenêtre: fenêtre) { return cache }
        let d = UserDefaults.standard
        if let capturée = d.object(forKey: Clés.météoDate) as? Date, météoFraîche(capturée, fenêtre: fenêtre) {
            // `object(as: Double?)` distingue « altitude absente » de « niveau de la mer (0 m) ».
            let altitude = d.object(forKey: Clés.météoAltitude) as? Double
            let snap = WeatherSnapshot(apparentTemperatureC: d.double(forKey: Clés.météoRessentie),
                                       altitudeM: altitude)
            météoCache = (snap, capturée)   // réhydrate le cache mémoire
            return (snap, capturée)
        }
        return nil
    }

    private func météoFraîche(_ date: Date, fenêtre: TimeInterval?) -> Bool {
        guard Calendar.current.isDate(date, inSameDayAs: .now) else { return false }
        guard let fenêtre else { return true }   // relevé du jour, quel que soit son âge
        return Date.now.timeIntervalSince(date) < fenêtre
    }

    @discardableResult
    private func mémoriserMétéo(_ snap: WeatherSnapshot) -> Date {
        let maintenant = Date.now
        météoCache = (snap, maintenant)
        let d = UserDefaults.standard
        d.set(snap.apparentTemperatureC, forKey: Clés.météoRessentie)
        if let altitude = snap.altitudeM {
            d.set(altitude, forKey: Clés.météoAltitude)
        } else {
            d.removeObject(forKey: Clés.météoAltitude)
        }
        d.set(maintenant, forKey: Clés.météoDate)
        return maintenant
    }

    /// Importe les prises d'eau saisies hors Wello (Watch, autres apps) en HydrationLog,
    /// dédupliquées par UUID HealthKit. SwiftData reste l'unique source de vérité du consommé.
    private func importerEauHealthKit() async -> Int {
        let début = Calendar.current.startOfDay(for: .now)
        let externes = await healthKit.prisesEauExternes(depuis: début)
        guard !externes.isEmpty else { return 0 }

        // Borné au jour : les externes récupérés le sont déjà (`depuis: début`), inutile de charger
        // tout l'historique importé à chaque refresh.
        let descripteur = FetchDescriptor<HydrationLog>(
            predicate: #Predicate { $0.healthKitUUID != nil && $0.loggedAt >= début }
        )
        let déjàImportés = Set((try? modelContext.fetch(descripteur))?.compactMap(\.healthKitUUID) ?? [])
        let pierres = pierresTombales   // imports supprimés à ne pas ressusciter

        var ajoutés = 0
        for prise in externes where !déjàImportés.contains(prise.id) && !pierres.contains(prise.id) {
            modelContext.insert(HydrationLog(amountML: prise.ml, loggedAt: prise.date,
                                             source: "healthkit", healthKitUUID: prise.id,
                                             drinkType: prise.drink.rawValue,
                                             coefficient: prise.coefficient))
            ajoutés += 1
        }
        return ajoutés
    }

    /// Détecte un workout fraîchement terminé (< 1h) et déclenche un rappel post-séance,
    /// sans re-notifier deux fois la même séance (dédup via UserDefaults).
    private func détecterPostSéance() async {
        guard let fin = await healthKit.dernierWorkoutTerminé() else { return }
        guard fin > Date.now.addingTimeInterval(-3600) else { return }   // terminé dans la dernière heure

        let clé = Clés.dernierPostSéance
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

    /// Coupe tous les rappels jusqu'à demain (bouton cloche de l'accueil). Persisté : un log
    /// ou un refresh qui suit dans la même journée ne doit pas silencieusement les reprogrammer.
    func couperRappelsAujourdhui() async {
        UserDefaults.standard.set(Date.now, forKey: Clés.rappelsCoupésDate)
        rappelsCoupésAujourdhui = true
        await notifications.désactiverPourLaJournée()
    }

    /// Réactive les rappels coupés pour aujourd'hui et les replanifie immédiatement.
    func réactiverRappelsAujourdhui() async {
        UserDefaults.standard.removeObject(forKey: Clés.rappelsCoupésDate)
        rappelsCoupésAujourdhui = false
        await refreshToday(force: true)
    }

    /// Annule les rappels déjà programmés, sans poser la coupure « pour aujourd'hui » (utilisé
    /// quand l'utilisateur désactive les rappels intelligents globalement au Profil ; distinct
    /// du bouton cloche pour ne pas bloquer une réactivation le jour même).
    func annulerRappelsProgrammés() async {
        await notifications.annulerTout()
    }

    /// Enregistre une prise (eau ou autre boisson) : SwiftData (source de vérité) + écriture
    /// HealthKit de l'hydratation effective positive (une boisson à effectif ≤ 0 n'écrit rien).
    func log(ml: Int, drink: DrinkType = .water, coefficient: Double = 1.0) async {
        let entrée = HydrationLog(amountML: ml, loggedAt: .now, source: "app",
                                  drinkType: drink.rawValue, coefficient: coefficient)
        modelContext.insert(entrée)
        // Avant l'écriture Santé : l'accueil réagit à l'insertion (jauge, fête d'objectif) et doit
        // lire une série déjà à jour — l'UUID d'échantillon posé plus bas n'affecte rien de tout ça.
        propagerChangement()

        let effectif = max(0, entrée.effectiveML)
        if effectif > 0 { entrée.healthSampleUUID = await healthKit.écrireEau(ml: effectif, date: entrée.loggedAt) }

        if let objectif = breakdown?.totalML {
            await planifierSelonPalier(objectifML: objectif)
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

        // Capture avant delete (l'objet ne doit plus être lu après `modelContext.delete`).
        let effectif = max(0, dernière.effectiveML)
        let date = dernière.loggedAt
        let source = dernière.source
        let sampleUUID = dernière.healthSampleUUID
        let importUUID = dernière.healthKitUUID
        modelContext.delete(dernière)
        propagerChangement()
        await nettoyerSantéAprèsSuppression(source: source, healthSampleUUID: sampleUUID,
                                            healthKitUUID: importUUID, effectif: effectif, date: date)

        if let objectif = breakdown?.totalML {
            await planifierSelonPalier(objectifML: objectif)
        }
    }

    /// Supprime une prise précise (depuis le détail d'un jour) : SwiftData + Santé (si saisie
    /// dans Wello) + replanification des rappels.
    func supprimer(_ log: HydrationLog) async {
        let effectif = max(0, log.effectiveML)
        let date = log.loggedAt
        let source = log.source
        let sampleUUID = log.healthSampleUUID
        let importUUID = log.healthKitUUID
        modelContext.delete(log)
        propagerChangement()
        await nettoyerSantéAprèsSuppression(source: source, healthSampleUUID: sampleUUID,
                                            healthKitUUID: importUUID, effectif: effectif, date: date)
        if let objectif = breakdown?.totalML {
            await planifierSelonPalier(objectifML: objectif)
        }
    }

    /// Après suppression d'une prise : retire l'échantillon Santé si Wello l'a écrit (par UUID,
    /// sinon repli montant+date), et pose une **pierre tombale** si c'était un import externe —
    /// sinon il serait réimporté le jour même par `importerEauHealthKit`.
    private func nettoyerSantéAprèsSuppression(source: String, healthSampleUUID: UUID?,
                                               healthKitUUID: UUID?, effectif: Int, date: Date) async {
        if source == "healthkit" {
            if let ext = healthKitUUID { ajouterPierreTombale(ext) }
            return   // échantillon d'une autre source : pas à nous de le supprimer
        }
        // Prise écrite par Wello (app ou watch) : suppression précise si l'UUID est connu.
        if healthSampleUUID != nil || effectif > 0 {
            await healthKit.supprimerEau(uuid: healthSampleUUID, ml: effectif, date: date)
        }
    }

    /// Replanifie les rappels selon le palier : `plus` (avec assez de données) → adaptatif ;
    /// sinon (gratuit ou cold-start) → rappels fixes existants. No-op si rappels désactivés.
    private func planifierSelonPalier(objectifML: Int) async {
        guard profilCourant().remindersEnabled else { return }
        // Bilan hebdomadaire (dimanche soir), récurrent et idempotent — tant que les rappels sont actifs.
        await notifications.programmerBilanHebdomadaire()
        // Coupure « pour aujourd'hui » : ne pas reprogrammer les rappels du jour (un log ou un
        // refresh qui suit ne doit pas silencieusement les ressusciter avant demain).
        guard !rappelsCoupésAujourdhui else { return }
        let consommé = consomméAujourdhui()
        let objectifAtteint = consommé >= objectifML

        if rappelsAdaptatifsDébloqués() {
            let historique = historiquePrises()
            if planner.aAssezDeDonnées(historique) {
                let fenêtre = await fenêtreÉveilCourante(historique: historique)
                let heures = planner.planRappels(historique: historique, fenêtre: fenêtre,
                                                 now: .now, objectifAtteint: objectifAtteint)
                étatRappels = ÉtatRappels(mode: .adaptatif, fenêtre: fenêtre)
                await notifications.planifierRappelsAdaptatifs(auxHeures: heures,
                                                               objectifML: objectifML,
                                                               consomméML: consommé,
                                                               fenêtre: fenêtre)
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

    /// Remise à zéro : prises, objectifs, profil et caches locaux disparaissent, les rappels sont
    /// annulés et la Live Activity terminée (objectif redevenu nul). `dansSantéAussi` supprime en
    /// plus les prises d'eau que **Wello** a écrites dans Santé.app (jamais celles des autres
    /// apps). Les achats Wello+ et les préférences d'affichage survivent : ce ne sont pas des
    /// données de suivi. L'app repart sur l'onboarding (profil vierge, sexe non renseigné).
    func effacerToutesLesDonnées(dansSantéAussi: Bool) async {
        tâcheRecalcul?.cancel()
        if dansSantéAussi { await healthKit.supprimerToutesNosPrisesEau() }

        try? modelContext.delete(model: HydrationLog.self)
        try? modelContext.delete(model: DailyGoal.self)
        try? modelContext.delete(model: UserProfile.self)

        let defaults = UserDefaults.standard
        for clé in Clés.toutesDonnéesDeSuivi { defaults.removeObject(forKey: clé) }

        météoCache = nil
        dernierRefresh = nil
        breakdown = nil
        météoIndisponible = false
        rappelsCoupésAujourdhui = false
        étatServices = ÉtatServices()
        étatRappels = ÉtatRappels()
        étatSources = ÉtatSourcesHydratation()

        await notifications.annulerTout()
        // Objectif redevenu nul : la Live Activity se termine, widgets et Watch repartent à vide.
        propagerChangement()
    }

    /// Recharge toutes les timelines de widget : à appeler après tout changement du consommé
    /// ou de l'objectif du jour.
    private func rechargerWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Point de passage unique après toute mutation du consommé ou de l'objectif du jour :
    /// série, widgets, Watch et Live Activity repartent ensemble.
    private func propagerChangement() {
        rafraîchirSérie()
        rechargerWidgets()
        pousserSnapshotWatch()
        rafraîchirLiveActivité()
    }

    /// Recalcule la série d'objectifs atteints : jours passés contigus (depuis les `DailyGoal`,
    /// avec leur consommé reconstitué), plus aujourd'hui s'il est atteint. Les deux fetchs sont
    /// bornés à `joursSérie` — l'historique complet n'est jamais chargé.
    private func rafraîchirSérie() {
        let cal = Calendar.current
        let aujourdhui = cal.startOfDay(for: .now)
        guard let horizon = cal.date(byAdding: .day, value: -Self.joursSérie, to: aujourdhui) else { return }

        let prises = FetchDescriptor<HydrationLog>(
            predicate: #Predicate { $0.loggedAt >= horizon && $0.loggedAt < aujourdhui })
        var conso: [Date: Int] = [:]
        for log in (try? modelContext.fetch(prises)) ?? [] {
            conso[cal.startOfDay(for: log.loggedAt), default: 0] += log.effectiveML
        }

        let objectifsPassés = FetchDescriptor<DailyGoal>(
            predicate: #Predicate { $0.date >= horizon && $0.date < aujourdhui },
            sortBy: [SortDescriptor(\.date, order: .reverse)])
        let passés = ((try? modelContext.fetch(objectifsPassés)) ?? []).map {
            DailyTotal(consumedML: clampedDayTotal(conso[cal.startOfDay(for: $0.date)] ?? 0),
                       goalML: $0.totalML)
        }

        let objectifDuJour = breakdown?.totalML ?? 0
        let atteintAujourdhui = objectifDuJour > 0 && consomméAujourdhui() >= objectifDuJour
        sérieCourante = HydrationStats.currentStreak(passés) + (atteintAujourdhui ? 1 : 0)
    }

    /// Construit le mirroir d'état destiné à la Watch à partir de l'objectif/consommé du jour,
    /// du profil minimal et des `id` de prises Watch déjà enregistrées (acquittées).
    private func snapshotWatch() -> WatchSyncSnapshot {
        let profil = profilCourant()
        let début = Calendar.current.startOfDay(for: .now)
        let desc = FetchDescriptor<HydrationLog>(
            predicate: #Predicate { $0.loggedAt >= début && $0.watchUUID != nil })
        let acquittés = ((try? modelContext.fetch(desc)) ?? []).compactMap(\.watchUUID)
        return WatchSyncSnapshot(
            objectifML: breakdown?.totalML ?? 0,
            consomméML: consomméAujourdhui(),
            quickAdds: profil.quickAdds,
            configuré: breakdown != nil,
            sexeRaw: profil.sexe?.rawValue,
            etatPhysioRaw: profil.etatPhysio == .aucun ? nil : profil.etatPhysio.rawValue,
            renalBonusML: profil.renalBonusEffectifML,
            activitySensitivity: profil.activitySensitivity,
            weatherSensitivity: profil.weatherSensitivity,
            manualAdjustmentML: profil.manualAdjustmentML,
            acquittés: acquittés,
            générémLe: .now)
    }

    /// Pousse l'état courant vers la Watch (à appeler après toute mutation, comme `rechargerWidgets`).
    private func pousserSnapshotWatch() {
        watchSync.pousser(snapshotWatch())
    }

    /// Actualise la Live Activity du jour avec le consommé/objectif courants (démarre au besoin).
    private func rafraîchirLiveActivité() {
        liveActivity.mettreÀJour(consomméML: consomméAujourdhui(), objectifML: breakdown?.totalML ?? 0)
    }

    /// Enregistre une prise reçue de la Watch (déduplication par `watchUUID`). Écrit l'eau dans
    /// Santé.app (l'iPhone reste l'unique écrivain HealthKit), replanifie les rappels, recharge
    /// widgets + Watch (avec l'`id` désormais acquitté).
    func enregistrerPriseDistante(_ prise: PriseWatch) async {
        let id = prise.id
        let déjàVue = FetchDescriptor<HydrationLog>(predicate: #Predicate { $0.watchUUID == id })
        if let existe = try? modelContext.fetch(déjàVue), !existe.isEmpty {
            pousserSnapshotWatch()   // déjà enregistrée : re-acquitter suffit
            return
        }
        let entrée = HydrationLog(amountML: prise.amountML, loggedAt: prise.loggedAt, source: "watch",
                                  drinkType: "water", coefficient: 1.0, watchUUID: id)
        modelContext.insert(entrée)
        propagerChangement()
        if entrée.effectiveML > 0 { entrée.healthSampleUUID = await healthKit.écrireEau(ml: entrée.effectiveML, date: entrée.loggedAt) }
        if let objectif = breakdown?.totalML {
            await planifierSelonPalier(objectifML: objectif)
        }
    }

    /// Reconstruit le `GoalBreakdown` du jour à partir du `DailyGoal` persisté, s'il existe.
    /// Sert à amorcer l'affichage au démarrage à froid avant le recalcul asynchrone. Le plafond
    /// de sécurité est déduit (total bridé sous le besoin physiologique).
    private func objectifDuJourPersisté() -> GoalBreakdown? {
        let jour = Calendar.current.startOfDay(for: .now)
        let descripteur = FetchDescriptor<DailyGoal>(predicate: #Predicate { $0.date == jour })
        guard let g = try? modelContext.fetch(descripteur).first else { return nil }
        let physiologique = g.baseML + g.activityBonusML + g.weatherBonusML + g.altitudeBonusML
            + g.lifeStageBonusML + g.renalBonusML + g.bodyBonusML + g.manualAdjustmentML
        return GoalBreakdown(baseML: g.baseML, activityBonusML: g.activityBonusML,
                             weatherBonusML: g.weatherBonusML, altitudeBonusML: g.altitudeBonusML,
                             lifeStageBonusML: g.lifeStageBonusML, renalBonusML: g.renalBonusML,
                             bodyBonusML: g.bodyBonusML, manualAdjustmentML: g.manualAdjustmentML,
                             totalML: g.totalML, plafondAppliqué: g.totalML < physiologique)
    }

    private func upsertDailyGoal(_ r: GoalBreakdown) {
        let jour = Calendar.current.startOfDay(for: .now)
        let descripteur = FetchDescriptor<DailyGoal>(predicate: #Predicate { $0.date == jour })

        if let goal = try? modelContext.fetch(descripteur).first {
            goal.baseML = r.baseML
            goal.activityBonusML = r.activityBonusML
            goal.weatherBonusML = r.weatherBonusML
            goal.altitudeBonusML = r.altitudeBonusML
            goal.lifeStageBonusML = r.lifeStageBonusML
            goal.renalBonusML = r.renalBonusML
            goal.bodyBonusML = r.bodyBonusML
            goal.manualAdjustmentML = r.manualAdjustmentML
            goal.totalML = r.totalML
            goal.calculatedAt = .now
        } else {
            let goal = DailyGoal(date: jour, baseML: r.baseML, activityBonusML: r.activityBonusML,
                                 weatherBonusML: r.weatherBonusML, altitudeBonusML: r.altitudeBonusML,
                                 lifeStageBonusML: r.lifeStageBonusML, renalBonusML: r.renalBonusML,
                                 bodyBonusML: r.bodyBonusML, manualAdjustmentML: r.manualAdjustmentML,
                                 totalML: r.totalML)
            modelContext.insert(goal)
        }
    }
}
