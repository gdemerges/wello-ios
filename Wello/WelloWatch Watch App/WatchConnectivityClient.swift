import Foundation
import OSLog
import WatchConnectivity
import WelloKit

/// Pont WatchConnectivity côté Watch : reçoit le mirroir d'état (`applicationContext`) et envoie
/// les prises (`transferUserInfo`, file à livraison garantie même iPhone injoignable).
///
/// `@unchecked Sendable` : `WCSession` est thread-safe ; l'unique état mutable (`onSnapshot`) est
/// fixé une fois au démarrage.
final class WatchConnectivityClient: NSObject, @unchecked Sendable {
    /// Journal dédié : Console.app (catégorie `watch-sync-watch`) pour suivre l'envoi des prises
    /// et la réception des snapshots au runtime.
    private static let log = Logger(subsystem: "Life.Wello", category: "watch-sync-watch")

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
        guard let session else {
            Self.log.error("envoi impossible : WCSession non supportée")
            return
        }
        let dict = prise.dictionnaire()
        session.transferUserInfo(dict)
        let reachable = session.isReachable
        if reachable {
            session.sendMessage(dict, replyHandler: nil) { error in
                Self.log.error("sendMessage échec : \(error.localizedDescription, privacy: .public)")
            }
        }
        Self.log.notice(
            "envoi \(prise.amountML)ml id=\(prise.id.uuidString, privacy: .public) via transferUserInfo\(reachable ? "+message" : "") reachable=\(reachable)")
    }
}

extension WatchConnectivityClient: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState,
                 error: Error?) {
        Self.log.notice("activation=\(state.rawValue) reachable=\(session.isReachable)")
        if let error { Self.log.error("activation en erreur : \(error.localizedDescription, privacy: .public)") }
        // Au démarrage, l'iPhone a peut-être déjà déposé un applicationContext : le consommer.
        let ctx = session.receivedApplicationContext
        if let snap = WatchSyncSnapshot(dictionnaire: ctx) {
            Self.log.notice("snapshot initial appliqué (objectif=\(snap.objectifML) consommé=\(snap.consomméML))")
            onSnapshot?(snap)
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        guard let snap = WatchSyncSnapshot(dictionnaire: context) else {
            Self.log.error("applicationContext reçu illisible")
            return
        }
        Self.log.notice("snapshot reçu (objectif=\(snap.objectifML) consommé=\(snap.consomméML) acquittés=\(snap.acquittés.count))")
        onSnapshot?(snap)
    }
}
