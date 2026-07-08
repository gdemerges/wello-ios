import Foundation
import SwiftUI
import WidgetKit
import WelloKit

/// Orchestrateur de l'app Watch. Détient l'`ÉtatHydratationWatch` (réconciliation pure), persiste
/// la file de prises locales (survit au relaunch), pousse les prises à l'iPhone et applique les
/// snapshots reçus. Source d'affichage : `progress`/`configuré`/`quickAdds`.
@MainActor
@Observable
final class WatchStore {
    private(set) var état = ÉtatHydratationWatch()

    private let connectivity: WatchConnectivityClient
    private let healthKit: HealthKitWatchService
    private let défauts = UserDefaults.standard
    private static let cléPrises = "wello.watch.prisesLocales"

    init(connectivity: WatchConnectivityClient = .init(),
         healthKit: HealthKitWatchService = .init()) {
        self.connectivity = connectivity
        self.healthKit = healthKit
        état = ÉtatHydratationWatch(prisesLocales: chargerPrises())
        connectivity.onSnapshot = { [weak self] snap in
            Task { @MainActor in self?.appliquer(snap) }
        }
    }

    var configuré: Bool { état.configuré }
    var progress: WidgetProgress { état.progress }
    var quickAdds: [Int] { état.quickAdds }

    /// Demande l'accès HealthKit et lit l'énergie active (recalcul autonome de l'objectif).
    /// Renvoie aussi les prises encore non acquittées (débloque celles coincées par une file
    /// `transferUserInfo` lente) ; la dédup `watchUUID` côté iPhone rend ce renvoi inoffensif.
    func démarrer() async {
        for prise in état.prisesEnAttente { connectivity.envoyer(prise) }
        await healthKit.requestAuthorization()
        état.mettreÀJourÉnergie(await healthKit.énergieActiveDuJour())
        publierComplication()   // l'objectif a pu monter via l'énergie active locale
    }

    /// Ajoute une prise : affichage optimiste + envoi à l'iPhone + persistance.
    func ajouter(ml: Int) {
        let prise = PriseWatch(amountML: ml)
        état.ajouterPrise(prise)
        connectivity.envoyer(prise)
        sauvegarderPrises()
        publierComplication()
    }

    /// Annule la dernière prise locale non encore acquittée (no-op sinon).
    func annulerDernière() {
        état.annulerDernièreEnAttente()
        sauvegarderPrises()
        publierComplication()
    }

    private func appliquer(_ snap: WatchSyncSnapshot) {
        état.appliquer(snap)
        sauvegarderPrises()   // purge des acquittées persistée
        publierComplication()
    }

    /// Publie l'état affichable vers la complication de cadran (process séparé) et demande son
    /// rafraîchissement. Appelé après toute mutation qui change progression ou objectif.
    private func publierComplication() {
        WelloWatchShared.écrire(progress: état.progress, configuré: état.configuré)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Persistance de la file locale

    private func chargerPrises() -> [PriseWatch] {
        guard let data = défauts.data(forKey: Self.cléPrises),
              let prises = try? JSONDecoder().decode([PriseWatch].self, from: data) else { return [] }
        return prises
    }

    private func sauvegarderPrises() {
        let data = try? JSONEncoder().encode(état.prisesLocales)
        défauts.set(data, forKey: Self.cléPrises)
    }
}
