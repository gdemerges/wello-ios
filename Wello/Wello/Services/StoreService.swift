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
    func statutActuel() async -> EntitlementStatus
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

/// Implémentation réelle via StoreKit 2.
struct StoreKitService: StoreServicing {

    func statutActuel() async -> EntitlementStatus {
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result,
               t.productID == StoreIDs.plusLifetime,
               t.revocationDate == nil {
                return .plus
            }
        }
        return .free
    }

    func produitPlus() async -> StoreProduct? {
        guard let p = try? await Product.products(for: [StoreIDs.plusLifetime]).first else {
            return nil
        }
        return StoreProduct(displayName: p.displayName, displayPrice: p.displayPrice)
    }

    func acheter() async throws -> PurchaseOutcome {
        guard let produit = try await Product.products(for: [StoreIDs.plusLifetime]).first else {
            return .pending
        }
        switch try await produit.purchase() {
        case .success(let verification):
            if case .verified(let t) = verification {
                await t.finish()
                return .success
            }
            return .pending
        case .userCancelled:
            return .userCancelled
        case .pending:
            return .pending
        @unknown default:
            return .pending
        }
    }

    func restaurer() async -> EntitlementStatus {
        try? await AppStore.sync()
        return await statutActuel()
    }

    func observerTransactions() -> AsyncStream<EntitlementStatus> {
        AsyncStream { continuation in
            let task = Task {
                for await result in Transaction.updates {
                    if case .verified(let t) = result {
                        await t.finish()
                        continuation.yield(t.revocationDate == nil ? .plus : .free)
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
