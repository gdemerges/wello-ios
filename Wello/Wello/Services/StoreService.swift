import Foundation
import StoreKit
import WelloKit

/// Produit premium tel qu'affiché à l'utilisateur (prix localisé par StoreKit).
struct StoreProduct: Sendable, Equatable {
    let displayName: String
    let displayPrice: String
}

/// Issue d'une tentative d'achat.
enum PurchaseOutcome: Sendable, Equatable {
    case success
    case userCancelled
    case pending
}

/// Accès au store (achat, statut, restauration). Mockable pour previews/dev.
protocol StoreServicing: Sendable {
    /// Statut d'entitlement courant (lecture locale StoreKit, valide offline après 1ʳᵉ synchro).
    func currentStatus() async -> EntitlementStatus
    /// Produit « Wello+ » avec prix localisé, ou nil si indisponible (réseau/StoreKit).
    func produitPlus() async -> StoreProduct?
    /// Lance l'achat du produit Wello+.
    func acheter() async throws -> PurchaseOutcome
    /// Restaure les achats puis renvoie le statut résultant.
    func restaurer() async -> EntitlementStatus
    /// Flux des changements de transaction (achats/remboursements hors app).
    func observerTransactions() -> AsyncStream<EntitlementStatus>
}

/// Identifiant du produit non-consommable (doit correspondre à App Store Connect + Wello.storekit).
enum StoreIDs {
    static let plusLifetime = "com.wello.plus.lifetime"
}
