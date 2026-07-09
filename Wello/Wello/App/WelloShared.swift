import Foundation
import SwiftData

/// Configuration partagée entre l'app et l'extension widget : identifiant d'App Group et
/// fabrique du `ModelContainer` pointant vers un store unique dans le conteneur d'App Group.
/// Effectue une migration unique du store local historique vers l'App Group au premier accès.
enum WelloShared {
    /// Doit correspondre à la capability App Group activée sur l'app ET l'extension widget.
    static let appGroupID = "group.Life.Wello"

    /// Store partagé, dans le conteneur d'App Group (lisible/écrivable par les deux cibles).
    /// `nil` quand l'App Group n'est pas résolu (ex. canvas de preview Xcode sans entitlement).
    static var sharedStoreURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("Wello.store")
    }

    /// Store local historique (créé par les versions pré-widget, container par défaut).
    private static var defaultStoreURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent("default.store")
    }

    /// Construit le `ModelContainer` partagé, après migration éventuelle du store local.
    /// Robuste au store corrompu : plutôt que de crasher au lancement (données sans sauvegarde
    /// cloud), on écarte le store fautif (renommé, donc récupérable) et on repart neuf ; en tout
    /// dernier recours, un store en mémoire garde l'app utilisable. Sans App Group résolu (canvas
    /// de preview Xcode), démarre directement en mémoire.
    static func makeModelContainer() -> ModelContainer {
        if let url = sharedStoreURL {
            migrerStoreSiNécessaire(storeURL: url)
            // 1. Ouverture normale.
            if let c = try? conteneur(ModelConfiguration(url: url)) { return c }
            // 2. Store illisible/corrompu : on l'écarte et on retente sur un store neuf.
            écarterStoreCorrompu(url)
            if let c = try? conteneur(ModelConfiguration(url: url)) { return c }
        }
        // 3. Dernier recours : en mémoire (données de session ; l'app reste pleinement utilisable).
        return try! conteneur(ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private static func conteneur(_ config: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(for: UserProfile.self, DailyGoal.self, HydrationLog.self,
                           configurations: config)
    }

    /// Renomme les 3 fichiers SQLite du store fautif en `.corrompu-<epoch>` (conserve les
    /// données pour une éventuelle récupération) afin qu'un store neuf puisse être recréé.
    private static func écarterStoreCorrompu(_ url: URL) {
        let fm = FileManager.default
        let suffixe = ".corrompu-\(Int(Date.now.timeIntervalSince1970))"
        for s in ["", "-wal", "-shm"] {
            let src = URL(fileURLWithPath: url.path + s)
            guard fm.fileExists(atPath: src.path) else { continue }
            try? fm.moveItem(at: src, to: URL(fileURLWithPath: url.path + s + suffixe))
        }
    }

    /// Copie une seule fois le store local vers l'App Group si ce dernier n'existe pas encore.
    /// Idempotent : ne fait rien une fois le store partagé présent (ou si aucun store local).
    private static func migrerStoreSiNécessaire(storeURL: URL) {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: storeURL.path),
              fm.fileExists(atPath: defaultStoreURL.path) else { return }
        // SQLite tient sur 3 fichiers : .store, -wal, -shm.
        for suffixe in ["", "-wal", "-shm"] {
            let src = URL(fileURLWithPath: defaultStoreURL.path + suffixe)
            let dst = URL(fileURLWithPath: storeURL.path + suffixe)
            if fm.fileExists(atPath: src.path) { try? fm.copyItem(at: src, to: dst) }
        }
    }
}
