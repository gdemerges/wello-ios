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
    /// Sans App Group résolu (canvas de preview Xcode), retombe sur un store en mémoire pour
    /// que les previews fonctionnent au lieu de planter sur un unwrap de `nil`.
    static func makeModelContainer() -> ModelContainer {
        let config: ModelConfiguration
        if let url = sharedStoreURL {
            migrerStoreSiNécessaire(storeURL: url)
            config = ModelConfiguration(url: url)
        } else {
            config = ModelConfiguration(isStoredInMemoryOnly: true)
        }
        return try! ModelContainer(for: UserProfile.self, DailyGoal.self, HydrationLog.self,
                                   configurations: config)
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
