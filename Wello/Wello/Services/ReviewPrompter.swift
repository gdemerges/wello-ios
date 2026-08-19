import Foundation
import OSLog
import WelloKit

/// Persistance et arbitrage de la demande d'avis App Store.
///
/// La **règle** (quand solliciter) vit dans `WelloKit.DemandeAvis`, testée en CLI ; cette classe
/// ne fait que garder les compteurs en `UserDefaults` et exposer un verdict au moment opportun.
/// Elle ne présente rien elle-même : l'appelant (une vue) déclenche `requestReview`, seule API
/// autorisée par Apple — c'est iOS qui décide *in fine* d'afficher l'invite ou non.
@MainActor
@Observable
final class ReviewPrompter {
    private static let clé = "wello.avis.état"

    private let défauts: UserDefaults
    /// Version courante (`CFBundleShortVersionString` seule : le numéro de build ne doit pas
    /// rouvrir le droit à une sollicitation).
    private let version: String
    private var état: ÉtatDemandeAvis

    init(défauts: UserDefaults = .standard,
         version: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") {
        self.défauts = défauts
        self.version = version
        if let données = défauts.data(forKey: Self.clé),
           let décodé = try? JSONDecoder().decode(ÉtatDemandeAvis.self, from: données) {
            self.état = décodé
        } else {
            self.état = ÉtatDemandeAvis()
        }
    }

    /// À appeler à chaque objectif quotidien atteint. Renvoie `true` s'il faut solliciter un avis
    /// maintenant — auquel cas la demande est comptabilisée immédiatement (une invite refusée par
    /// iOS reste consommée : c'est le comportement voulu, on ne réessaie pas en boucle).
    func objectifAtteint(maintenant: Date = .now) -> Bool {
        état = DemandeAvis.aprèsObjectifAtteint(état: état)
        guard DemandeAvis.doitDemander(état: état, versionCourante: version, maintenant: maintenant) else {
            enregistrer()
            return false
        }
        état = DemandeAvis.aprèsDemande(état: état, versionCourante: version, maintenant: maintenant)
        enregistrer()
        WelloLog.app.notice("demande d'avis sollicitée (version \(self.version, privacy: .public))")
        return true
    }

    private func enregistrer() {
        guard let données = try? JSONEncoder().encode(état) else { return }
        défauts.set(données, forKey: Self.clé)
    }
}
