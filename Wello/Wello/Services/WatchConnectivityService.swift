import Foundation
import WatchConnectivity
import WelloKit

/// Pont WatchConnectivity côté iPhone. Pousse le mirroir d'état (`updateApplicationContext`,
/// coalescé) et reçoit les prises saisies au poignet (`transferUserInfo`) qu'il relaie via
/// `onPriseDistante`. Dégrade silencieusement si aucune Watch n'est jumelée/supportée.
///
/// `@unchecked Sendable` : `WCSession` est thread-safe ; l'unique état mutable (`onPriseDistante`)
/// est fixé une fois au démarrage.
final class WatchConnectivityService: NSObject, WatchSyncing, @unchecked Sendable {
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
        guard let session, session.activationState == .activated else { return }
        try? session.updateApplicationContext(snapshot.dictionnaire())
    }
}

extension WatchConnectivityService: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState,
                 error: Error?) {
        print("WELLO-WC iPhone activation=\(state.rawValue) paired=\(session.isPaired) installed=\(session.isWatchAppInstalled) reachable=\(session.isReachable) err=\(String(describing: error))")
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        print("WELLO-WC iPhone didReceiveUserInfo \(userInfo)")
        if let prise = PriseWatch(dictionnaire: userInfo) { onPriseDistante?(prise) }
    }

    // Canal temps réel (iPhone joignable) : même charge utile que `transferUserInfo`.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        print("WELLO-WC iPhone didReceiveMessage \(message)")
        if let prise = PriseWatch(dictionnaire: message) { onPriseDistante?(prise) }
    }

    // Requis sur iOS (gestion du changement de Watch jumelée).
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
