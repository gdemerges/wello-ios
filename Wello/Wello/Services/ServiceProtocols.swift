import Foundation
import WelloKit

/// Lecture/écriture HealthKit. Toutes les opérations dégradent gracieusement si refusé.
protocol HealthKitServicing: Sendable {
    /// Demande les autorisations (lecture workouts+poids, écriture eau). Sans effet si déjà décidé.
    func requestAuthorization() async
    /// Minutes d'effort cumulées des workouts du jour. 0 si indisponible/refusé.
    func minutesEffortDuJour() async -> Int
    /// Dernier poids connu en kg, ou nil si indisponible/refusé.
    func dernierPoids() async -> Double?
    /// Écrit une prise d'eau dans Santé.app. No-op si refusé.
    func écrireEau(ml: Int, date: Date) async
    /// Supprime de Santé.app l'échantillon d'eau du montant et de la date donnés (celui
    /// écrit par Wello). Best-effort : no-op si introuvable, refusé ou indisponible.
    func supprimerEau(ml: Int, date: Date) async
    /// Durée totale (minutes) des workouts terminés depuis `date`. Sert au rappel post-séance.
    func minutesEffortDepuis(_ date: Date) async -> Int
    /// Date de fin du workout le plus récent, ou nil. Sert à détecter une séance fraîchement terminée.
    func dernierWorkoutTerminé() async -> Date?
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

/// Planification des rappels d'hydratation.
protocol NotificationServicing: Sendable {
    func requestAuthorization() async -> Bool
    /// (Re)planifie les rappels du jour selon l'objectif et le consommé.
    func planifierRappels(objectifML: Int, consomméML: Int) async
    /// Programme un rappel post-séance (+500 ml dans l'heure).
    func programmerRappelPostSéance() async
    /// Reprogramme un rappel « plus tard » dans 1h (action snooze depuis une notification).
    func programmerSnooze() async
    /// Annule tous les rappels (toggle off / désactiver pour la journée).
    func annulerTout() async
    /// Désactive les rappels jusqu'à demain matin.
    func désactiverPourLaJournée() async
}
