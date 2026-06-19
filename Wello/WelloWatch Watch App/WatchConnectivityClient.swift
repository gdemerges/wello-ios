import Foundation
import WatchConnectivity
import WelloKit

/// Pont WatchConnectivity côté Watch : reçoit le mirroir d'état (`applicationContext`) et envoie
/// les prises (`transferUserInfo`, file à livraison garantie même iPhone injoignable).
///
/// `@unchecked Sendable` : `WCSession` est thread-safe ; l'unique état mutable (`onSnapshot`) est
/// fixé une fois au démarrage.
final class WatchConnectivityClient: NSObject, @unchecked Sendable {
    /// Branché par le `WatchStore` : appelé à chaque snapshot reçu de l'iPhone.
    var onSnapshot: (@Sendable (WatchSyncSnapshot) -> Void)?

    private let session: WCSession?

    override init() {
        session = WCSession.isSupported() ? .default : nil
        super.init()
        session?.delegate = self
        session?.activate()
    }

    /// Envoie une prise à l'iPhone. Double canal : `transferUserInfo` (file garantie, survit au
    /// hors-ligne) **et** `sendMessage` instantané quand l'iPhone est joignable (latence ~nulle,
    /// fiable même en simulateur). La déduplication par `watchUUID` côté iPhone rend la double
    /// livraison inoffensive.
    func envoyer(_ prise: PriseWatch) {
        guard let session else { print("WELLO-WC watch envoyer: pas de session"); return }
        let dict = prise.dictionnaire()
        print("WELLO-WC watch envoyer state=\(session.activationState.rawValue) reachable=\(session.isReachable) \(dict)")
        session.transferUserInfo(dict)
        if session.isReachable {
            session.sendMessage(dict, replyHandler: nil) { err in
                print("WELLO-WC watch sendMessage ERROR \(err.localizedDescription)")
            }
        }
    }
}

extension WatchConnectivityClient: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState,
                 error: Error?) {
        print("WELLO-WC watch activation=\(state.rawValue) reachable=\(session.isReachable) err=\(String(describing: error))")
        // Au démarrage, l'iPhone a peut-être déjà déposé un applicationContext : le consommer.
        let ctx = session.receivedApplicationContext
        if let snap = WatchSyncSnapshot(dictionnaire: ctx) { onSnapshot?(snap) }
    }

    func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        if let snap = WatchSyncSnapshot(dictionnaire: context) { onSnapshot?(snap) }
    }
}
