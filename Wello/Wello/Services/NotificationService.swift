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
    private let rédacteur = RappelRédacteur()

    init() {
        let logger = UNNotificationAction(identifier: Self.actionLog250,
                                          title: String(localized: "Logger 250 ml"), options: [])
        let snooze = UNNotificationAction(identifier: Self.actionSnooze,
                                          title: String(localized: "Plus tard (1h)"), options: [])
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

        // Rappel de retard à 14h et 17h (dans la fenêtre autorisée 7h–21h). Corps
        // contextualisé sur la fenêtre d'éveil par défaut (pas d'apprentissage en mode fixe).
        await programmerRappelHoraire(heure: 14, id: "wello.14h",
                                      objectifML: objectifML, consomméML: consomméML)
        await programmerRappelHoraire(heure: 17, id: "wello.17h",
                                      objectifML: objectifML, consomméML: consomméML)
    }

    func planifierRappelsAdaptatifs(auxHeures heures: [Date], objectifML: Int,
                                    consomméML: Int, fenêtre: FenêtreÉveil) async {
        // Purge fixes + adaptatifs avant de reposer (recalcul à chaque log/refresh).
        center.removePendingNotificationRequests(withIdentifiers: Self.idsFixes + Self.idsAdaptatifs)
        let cal = Calendar.current
        for (i, date) in heures.prefix(AdaptiveReminderPlanner.plafondParJour).enumerated() {
            let c = cal.dateComponents([.hour, .minute], from: date)
            let heureMin = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            let message = rédacteur.message(heureRappelMin: heureMin, objectifML: objectifML,
                                            consomméML: consomméML, fenêtre: fenêtre)
            let contenu = UNMutableNotificationContent()
            contenu.title = String(localized: "Hydratation")
            contenu.body = corps(message)
            contenu.categoryIdentifier = Self.catégorieRappel
            contenu.sound = .default
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let req = UNNotificationRequest(identifier: "wello.adaptif.\(i)", content: contenu, trigger: trigger)
            try? await center.add(req)
        }
    }

    private func programmerRappelHoraire(heure: Int, id: String,
                                         objectifML: Int, consomméML: Int) async {
        let message = rédacteur.message(heureRappelMin: heure * 60, objectifML: objectifML,
                                        consomméML: consomméML, fenêtre: .défaut)
        let contenu = UNMutableNotificationContent()
        contenu.title = String(localized: "Hydratation")
        contenu.body = corps(message)
        contenu.categoryIdentifier = Self.catégorieRappel
        contenu.sound = .default

        var comps = DateComponents()
        comps.hour = heure
        comps.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let req = UNNotificationRequest(identifier: id, content: contenu, trigger: trigger)
        try? await center.add(req)
    }

    /// Traduit un `MessageRappel` (sémantique, WelloKit) en corps de notification localisé.
    /// Clés stables + `%lld` (convention du catalogue) plutôt qu'une clé interpolée.
    private func corps(_ message: MessageRappel) -> String {
        let clé: String
        switch message.ton {
        case .enAvance:     clé = "rappel.enAvance"
        case .dansLesTemps: clé = "rappel.dansLesTemps"
        case .enRetard:     clé = "rappel.enRetard"
        case .grosRetard:   clé = "rappel.grosRetard"
        }
        return String(format: NSLocalizedString(clé, comment: "Corps de rappel d'hydratation"),
                      message.restantML)
    }

    func programmerBilanHebdomadaire() async {
        // Récurrent chaque dimanche 19h. Sans catégorie : la notif ouvre l'app (pas d'action +250).
        center.removePendingNotificationRequests(withIdentifiers: ["wello.bilanhebdo"])
        let contenu = UNMutableNotificationContent()
        contenu.title = String(localized: "Ton bilan de la semaine")
        contenu.body = String(localized: "Jours atteints, moyenne, tendance — jette un œil 📊")
        contenu.sound = .default

        var comps = DateComponents()
        comps.weekday = 1   // dimanche (1 = dimanche dans le calendrier grégorien)
        comps.hour = 19
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let req = UNNotificationRequest(identifier: "wello.bilanhebdo", content: contenu, trigger: trigger)
        try? await center.add(req)
    }

    func programmerRappelPostSéance() async {
        let contenu = UNMutableNotificationContent()
        contenu.title = String(localized: "Bien joué pour ta séance 💪")
        contenu.body = String(localized: "Bois ~500 ml dans l'heure pour récupérer.")
        contenu.categoryIdentifier = Self.catégorieRappel
        contenu.sound = .default

        // Dans 5 min ; on évite de superposer aux rappels horaires (jamais deux rapprochés).
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5 * 60, repeats: false)
        let req = UNNotificationRequest(identifier: "wello.postseance", content: contenu, trigger: trigger)
        try? await center.add(req)
    }

    func programmerSnooze() async {
        let contenu = UNMutableNotificationContent()
        contenu.title = String(localized: "Hydratation")
        contenu.body = String(localized: "Petit rappel : pense à boire 💧")
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
