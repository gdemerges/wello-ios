import Foundation
import WelloKit

/// Source de vérité du statut premium pour les vues. Injecté via `.environment`.
/// Lit StoreKit au démarrage, écoute les transactions, et cache le dernier statut connu
/// en UserDefaults pour afficher l'UI correcte dès le lancement (avant la résolution async).
@MainActor
@Observable
final class EntitlementStore {
    private let store: StoreServicing
    private(set) var status: EntitlementStatus
    private var updatesTask: Task<Void, Never>?

    private static let cacheKey = "wello.premium.status"

    init(store: StoreServicing) {
        self.store = store
        // Dernier statut connu : évite de verrouiller un client payant le temps de la résolution.
        self.status = (UserDefaults.standard.string(forKey: Self.cacheKey) == "plus") ? .plus : .free
    }

    /// Vrai si la feature est débloquée au palier courant.
    func isUnlocked(_ feature: PremiumFeature) -> Bool {
        Entitlements(status: status).isUnlocked(feature)
    }

    /// À appeler une fois au démarrage : résout le statut réel et écoute les transactions.
    func démarrer() async {
        appliquer(await store.statutActuel())
        updatesTask = Task { [weak self] in
            guard let stream = self?.store.observerTransactions() else { return }
            for await nouveau in stream {
                self?.appliquer(nouveau)
            }
        }
    }

    /// Produit Wello+ (prix localisé) pour le paywall.
    func produit() async -> StoreProduct? {
        await store.produitPlus()
    }

    /// Lance l'achat ; met à jour le statut en cas de succès.
    func acheterPlus() async throws -> PurchaseOutcome {
        let résultat = try await store.acheter()
        if résultat == .success { appliquer(.plus) }
        return résultat
    }

    /// Restaure les achats et met à jour le statut.
    func restaurer() async {
        appliquer(await store.restaurer())
    }

    private func appliquer(_ nouveau: EntitlementStatus) {
        status = nouveau
        UserDefaults.standard.set(nouveau == .plus ? "plus" : "free", forKey: Self.cacheKey)
    }
}
