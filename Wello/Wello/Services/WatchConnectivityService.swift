import Foundation
import OSLog
import WatchConnectivity
import WelloKit

/// Pont WatchConnectivity côté iPhone. Pousse le mirroir d'état (`updateApplicationContext`,
/// coalescé) et reçoit les prises saisies au poignet (`transferUserInfo`) qu'il relaie via
/// `onPriseDistante`. Dégrade silencieusement si aucune Watch n'est jumelée/supportée.
///
/// `@unchecked Sendable` : `WCSession` est thread-safe ; l'unique état mutable (`onPriseDistante`)
/// est fixé une fois au démarrage.
final class WatchConnectivityService: NSObject, WatchSyncing, @unchecked Sendable {
    /// Journal dédié : `log stream --predicate 'subsystem == "Life.Wello"'` (ou Console.app,
    /// catégorie `watch-sync-phone`) pour diagnostiquer la sync Watch→iPhone au runtime.
    private static let log = Logger(subsystem: "Life.Wello", category: "watch-sync-phone")

    /// Branché par l'app : appelé à chaque prise reçue de la Watch.
    var onPriseDistante: (@Sendable (PriseWatch) -> Void)?

    private let session: WCSession?

    override init() {
        session = WCSession.isSupported() ? .default : nil
        super.init()
        session?.delegate = self
        session?.activate()
    }

    func pousser(_ snapshot: WatchSyncSnapshot) {
        guard let session, session.activationState == .activated else {
            Self.log.debug("pousser ignoré : session non activée")
            return
        }
        do {
            try session.updateApplicationContext(snapshot.dictionnaire())
        } catch {
            Self.log.error("updateApplicationContext a échoué : \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension WatchConnectivityService: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState,
                 error: Error?) {
        // Les 3 indicateurs à vérifier si la sync ne remonte pas : jumelage, app installée, joignabilité.
        Self.log.notice(
            "activation=\(state.rawValue) paired=\(session.isPaired) watchAppInstalled=\(session.isWatchAppInstalled) reachable=\(session.isReachable)")
        if let error { Self.log.error("activation en erreur : \(error.localizedDescription, privacy: .public)") }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let prise = PriseWatch(dictionnaire: userInfo) else {
            Self.log.error("userInfo reçu illisible")
            return
        }
        Self.log.notice("prise reçue (userInfo) \(prise.amountML)ml id=\(prise.id.uuidString, privacy: .public)")
        onPriseDistante?(prise)
    }

    // Canal temps réel (iPhone joignable) : même charge utile que `transferUserInfo`.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let prise = PriseWatch(dictionnaire: message) else {
            Self.log.error("message reçu illisible")
            return
        }
        Self.log.notice("prise reçue (message) \(prise.amountML)ml id=\(prise.id.uuidString, privacy: .public)")
        onPriseDistante?(prise)
    }

    // Requis sur iOS (gestion du changement de Watch jumelée).
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
