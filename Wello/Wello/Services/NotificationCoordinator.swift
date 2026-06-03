import Foundation
import UserNotifications

/// Délégué des notifications : traite les actions directes (logger 250 ml, snooze) et
/// affiche les rappels même lorsque l'app est au premier plan. Réutilise `HydrationStore`
/// pour rester DRY (mêmes chemins de log/replanification que l'UI).
///
/// `@unchecked Sendable` : ne détient qu'une référence au store `@MainActor` (lui-même
/// `Sendable`), accédée uniquement via `await`.
final class NotificationCoordinator: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    private let store: HydrationStore

    init(store: HydrationStore) {
        self.store = store
        super.init()
    }

    /// Affiche bannière + son même app ouverte.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /// Traite le tap sur une action de notification.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        switch response.actionIdentifier {
        case NotificationService.actionLog250:
            await store.log(ml: 250)
        case NotificationService.actionSnooze:
            await store.snoozerRappels()
        default:
            break
        }
    }
}
