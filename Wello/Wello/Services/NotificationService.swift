import Foundation
import UserNotifications
import WelloKit

/// Planifie les rappels d'hydratation : fenêtre 7h–21h, jamais deux rapprochés,
/// rappel post-séance, et rappels de retard à 14h et 17h. Action directe « logger 250 ml ».
///
/// `@unchecked Sendable` : `UNUserNotificationCenter` est un singleton thread-safe.
final class NotificationService: NotificationServicing, @unchecked Sendable {

    static let actionLog250 = "WELLO_LOG_250"
    static let actionSnooze = "WELLO_SNOOZE"
    static let catégorieRappel = "WELLO_RAPPEL"
    private static var idsAdaptatifs: [String] {
        (0..<AdaptiveReminderPlanner.plafondParJour).map { "wello.adaptif.\($0)" }
    }
    private static let idsFixes = ["wello.14h", "wello.17h"]

    private let center = UNUserNotificationCenter.current()

    init() {
        let logger = UNNotificationAction(identifier: Self.actionLog250,
                                          title: "Logger 250 ml", options: [])
        let snooze = UNNotificationAction(identifier: Self.actionSnooze,
                                          title: "Plus tard (1h)", options: [])
        let catégorie = UNNotificationCategory(identifier: Self.catégorieRappel,
                                               actions: [logger, snooze], intentIdentifiers: [])
        center.setNotificationCategories([catégorie])
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func autorisationAccordée() async -> Bool {
        let réglages = await center.notificationSettings()
        return réglages.authorizationStatus == .authorized || réglages.authorizationStatus == .provisional
    }

    func planifierRappels(objectifML: Int, consomméML: Int) async {
        // On repart d'une ardoise propre : fixes ET adaptatifs (changement de palier possible).
        center.removePendingNotificationRequests(withIdentifiers: Self.idsFixes + Self.idsAdaptatifs)

        // Rappel de retard à 14h et 17h (dans la fenêtre autorisée 7h–21h).
        await programmerRappelHoraire(heure: 14, id: "wello.14h")
        await programmerRappelHoraire(heure: 17, id: "wello.17h")
    }

    func planifierRappelsAdaptatifs(auxHeures heures: [Date]) async {
        // Purge fixes + adaptatifs avant de reposer (recalcul à chaque log/refresh).
        center.removePendingNotificationRequests(withIdentifiers: Self.idsFixes + Self.idsAdaptatifs)
        for (i, date) in heures.prefix(AdaptiveReminderPlanner.plafondParJour).enumerated() {
            let contenu = UNMutableNotificationContent()
            contenu.title = "Hydratation"
            contenu.body = "Tu n'as pas bu depuis un moment — un verre d'eau 💧 ?"
            contenu.categoryIdentifier = Self.catégorieRappel
            contenu.sound = .default
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let req = UNNotificationRequest(identifier: "wello.adaptif.\(i)", content: contenu, trigger: trigger)
            try? await center.add(req)
        }
    }

    private func programmerRappelHoraire(heure: Int, id: String) async {
        let contenu = UNMutableNotificationContent()
        contenu.title = "Hydratation"
        contenu.body = "Pense à boire pour rester sur ton objectif du jour."
        contenu.categoryIdentifier = Self.catégorieRappel
        contenu.sound = .default

        var comps = DateComponents()
        comps.hour = heure
        comps.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let req = UNNotificationRequest(identifier: id, content: contenu, trigger: trigger)
        try? await center.add(req)
    }

    func programmerRappelPostSéance() async {
        let contenu = UNMutableNotificationContent()
        contenu.title = "Bien joué pour ta séance 💪"
        contenu.body = "Bois ~500 ml dans l'heure pour récupérer."
        contenu.categoryIdentifier = Self.catégorieRappel
        contenu.sound = .default

        // Dans 5 min ; on évite de superposer aux rappels horaires (jamais deux rapprochés).
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5 * 60, repeats: false)
        let req = UNNotificationRequest(identifier: "wello.postseance", content: contenu, trigger: trigger)
        try? await center.add(req)
    }

    func programmerSnooze() async {
        let contenu = UNMutableNotificationContent()
        contenu.title = "Hydratation"
        contenu.body = "Petit rappel : pense à boire 💧"
        contenu.categoryIdentifier = Self.catégorieRappel
        contenu.sound = .default

        // Reprogrammé dans 1h (action « Plus tard »).
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 60 * 60, repeats: false)
        let req = UNNotificationRequest(identifier: "wello.snooze", content: contenu, trigger: trigger)
        try? await center.add(req)
    }

    func annulerTout() async {
        center.removeAllPendingNotificationRequests()
    }

    func désactiverPourLaJournée() async {
        // Annule tout ; les rappels seront reprogrammés au prochain refresh de demain.
        center.removeAllPendingNotificationRequests()
    }
}
