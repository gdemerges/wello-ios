import Foundation
import WelloKit

/// Une prise importée de Santé.app (source externe à Wello) : eau exacte ou alcool générique.
struct PriseEauExterne: Sendable, Identifiable {
    let id: UUID          // UUID de l'échantillon HealthKit (clé de déduplication)
    let ml: Int
    let date: Date
    let drink: DrinkType
    let coefficient: Double

    init(id: UUID, ml: Int, date: Date, drink: DrinkType = .water, coefficient: Double = 1.0) {
        self.id = id
        self.ml = ml
        self.date = date
        self.drink = drink
        self.coefficient = coefficient
    }
}

/// Lecture/écriture HealthKit. Toutes les opérations dégradent gracieusement si refusé.
protocol HealthKitServicing: Sendable {
    /// Demande les autorisations (lecture workouts+énergie, écriture eau). Sans effet si déjà décidé.
    func requestAuthorization() async
    /// Énergie active (kcal) brûlée en séances aujourd'hui. 0 si indisponible/refusé.
    func énergieActiveDuJour() async -> Double
    /// Écrit une prise d'eau dans Santé.app et renvoie l'UUID de l'échantillon créé (pour
    /// pouvoir le supprimer précisément ensuite). nil si refusé/indisponible.
    func écrireEau(ml: Int, date: Date) async -> UUID?
    /// Supprime de Santé.app l'échantillon d'eau écrit par Wello. Par `uuid` si connu (identité
    /// exacte) ; sinon repli sur la correspondance montant+date (prises anté-`healthSampleUUID`).
    /// Best-effort : no-op si introuvable, refusé ou indisponible.
    func supprimerEau(uuid: UUID?, ml: Int, date: Date) async
    /// Prises d'eau (`dietaryWater`) et consommation d'alcool (`numberOfAlcoholicBeverages`)
    /// enregistrées depuis `date` par d'AUTRES sources que Wello. Vide si refusé.
    func prisesEauExternes(depuis date: Date) async -> [PriseEauExterne]
    /// Date de fin du workout le plus récent, ou nil. Sert à détecter une séance fraîchement terminée.
    func dernierWorkoutTerminé() async -> Date?
    /// Périodes de sommeil (asleep) depuis `date`, pour déduire la fenêtre d'éveil.
    /// Vide si refusé/indisponible.
    func périodesSommeil(depuis date: Date) async -> [PériodeSommeil]
}

/// Récupération météo best-effort.
protocol WeatherServicing: Sendable {
    /// Météo du jour pour des coordonnées. nil si réseau/API indisponible.
    func météoDuJour(latitude: Double, longitude: Double) async -> WeatherSnapshot?
}

/// Localisation one-shot pour alimenter la météo.
protocol LocationServicing: Sendable {
    /// Coordonnées actuelles, ou nil si refusé/indisponible.
    func coordonnéesActuelles() async -> (latitude: Double, longitude: Double)?
}

/// Pont WatchConnectivity côté iPhone : pousse l'état d'hydratation vers la Watch.
/// La réception des prises Watch passe par une closure branchée à l'app (cf. WelloApp).
protocol WatchSyncing: Sendable {
    /// Pousse le dernier état (mirroir coalescé). No-op si aucune Watch n'est jumelée.
    func pousser(_ snapshot: WatchSyncSnapshot)
}

/// Planification des rappels d'hydratation.
protocol NotificationServicing: Sendable {
    func requestAuthorization() async -> Bool
    /// État courant de l'autorisation, sans déclencher de demande. Pour l'affichage du diagnostic.
    func autorisationAccordée() async -> Bool
    /// (Re)planifie les rappels du jour selon l'objectif et le consommé.
    func planifierRappels(objectifML: Int, consomméML: Int) async
    /// (Re)planifie les rappels adaptatifs aux heures données (purge les rappels fixes
    /// et adaptatifs précédents). Plafonné par `AdaptiveReminderPlanner.plafondParJour`.
    /// Le corps de chaque rappel est contextualisé (moment de la journée + retard réel sur
    /// le rythme attendu) à partir de l'objectif, du consommé et de la fenêtre d'éveil.
    func planifierRappelsAdaptatifs(auxHeures heures: [Date], objectifML: Int,
                                    consomméML: Int, fenêtre: FenêtreÉveil) async
    /// Programme (idempotent) la notification hebdomadaire de bilan (dimanche soir, récurrente).
    func programmerBilanHebdomadaire() async
    /// Programme un rappel post-séance (+500 ml dans l'heure).
    func programmerRappelPostSéance() async
    /// Reprogramme un rappel « plus tard » dans 1h (action snooze depuis une notification).
    func programmerSnooze() async
    /// Annule tous les rappels (toggle off / désactiver pour la journée).
    func annulerTout() async
    /// Désactive les rappels jusqu'à demain matin.
    func désactiverPourLaJournée() async
}
