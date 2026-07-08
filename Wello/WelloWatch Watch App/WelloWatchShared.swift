import Foundation
import WelloKit

/// Pont de données **app Watch → complication de cadran**. La complication tourne dans un process
/// séparé : elle ne peut pas lire l'`ÉtatHydratationWatch` en mémoire. L'app Watch écrit donc son
/// dernier `WidgetProgress` dans un conteneur App Group **local à l'Apple Watch** ; la complication
/// le relit. Pas de réseau, pas de CloudKit — simple `UserDefaults` partagé.
///
/// Membre des **deux** cibles : `WelloWatch Watch App` (écrivain) et `WelloWatchWidget` (lecteur).
enum WelloWatchShared {
    /// Même identifiant d'App Group que côté iPhone. Les conteneurs sont **par appareil** : celui-ci
    /// est local à la Watch, distinct du conteneur iPhone du même identifiant.
    static let suiteName = "group.Life.Wello"

    private enum Clé {
        static let consommé = "wello.watch.consomméML"
        static let objectif = "wello.watch.objectifML"
        static let configuré = "wello.watch.configuré"
    }

    private static var defaults: UserDefaults { UserDefaults(suiteName: suiteName) ?? .standard }

    /// Écrit le dernier état affichable. Appelé par le `WatchStore` à chaque changement.
    static func écrire(progress: WidgetProgress, configuré: Bool) {
        let d = defaults
        d.set(progress.consomméML, forKey: Clé.consommé)
        d.set(progress.objectifML, forKey: Clé.objectif)
        d.set(configuré, forKey: Clé.configuré)
    }

    /// Relit le dernier état. Appelé par le `Provider` de la complication.
    static func lire() -> (progress: WidgetProgress, configuré: Bool) {
        let d = defaults
        return (WidgetProgress(consomméML: d.integer(forKey: Clé.consommé),
                               objectifML: d.integer(forKey: Clé.objectif)),
                d.bool(forKey: Clé.configuré))
    }
}
