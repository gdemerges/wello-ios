import Foundation
import StoreKit
import WelloKit

/// Type d'offre Wello+ présentée au paywall.
enum ProductKind: Sendable, Equatable {
    case annual      // abonnement auto-renouvelable
    case lifetime    // achat unique non-consommable
}

/// Produit premium tel qu'affiché à l'utilisateur (prix localisé par StoreKit).
struct StoreProduct: Sendable, Equatable, Identifiable {
    let id: String
    let kind: ProductKind
    let displayName: String
    let displayPrice: String
    /// Libellé d'offre d'introduction (ex. « Essai gratuit : 1 semaine »), nil si aucune.
    let offreIntro: String?
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
    /// Produits Wello+ disponibles (abonnement annuel + achat à vie), prix localisés.
    /// Annuel d'abord (mis en avant), puis à vie. Vide si indisponible (réseau/StoreKit).
    func produits() async -> [StoreProduct]
    /// Lance l'achat du produit d'identifiant donné.
    func acheter(_ productID: String) async throws -> PurchaseOutcome
    /// Restaure les achats puis renvoie le statut résultant.
    func restaurer() async -> EntitlementStatus
    /// Flux des changements de transaction (achats/renouvellements/remboursements hors app).
    func observerTransactions() -> AsyncStream<EntitlementStatus>
}

/// Identifiants des produits (doivent correspondre à App Store Connect + Wello.storekit).
/// Wello+ est accordé par l'abonnement annuel OU l'achat à vie : n'importe lequel actif suffit.
enum StoreIDs {
    static let plusAnnual = "com.wello.plus.annual"
    static let plusLifetime = "com.wello.plus.lifetime"
    static let tous: Set<String> = [plusAnnual, plusLifetime]
}

/// Implémentation réelle via StoreKit 2.
struct StoreKitService: StoreServicing {

    func statutActuel() async -> EntitlementStatus {
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result,
               StoreIDs.tous.contains(t.productID),
               t.revocationDate == nil {
                return .plus
            }
        }
        return .free
    }

    func produits() async -> [StoreProduct] {
        guard let produits = try? await Product.products(for: StoreIDs.tous) else { return [] }
        // Ordre stable : annuel d'abord (mis en avant), puis à vie.
        return produits
            .map(descripteur)
            .sorted { classement($0.kind) < classement($1.kind) }
    }

    func acheter(_ productID: String) async throws -> PurchaseOutcome {
        guard let produit = try await Product.products(for: [productID]).first else {
            return .pending
        }
        switch try await produit.purchase() {
        case .success(let verification):
            switch verification {
            case .verified(let t):
                await t.finish()
                return .success
            case .unverified(let t, _):
                await t.finish()   // vide la file ; aucun accès accordé sur une transaction non vérifiée
                return .pending
            }
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
                    if case .verified(let t) = result { await t.finish() }
                    // Renouvellement, expiration ou remboursement : on réévalue l'entitlement
                    // complet (les deux produits confondus) plutôt que d'inférer d'une seule transaction.
                    continuation.yield(await statutActuel())
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Convertit un `Product` StoreKit en modèle d'affichage, avec libellé d'offre d'intro.
    private func descripteur(_ produit: Product) -> StoreProduct {
        let kind: ProductKind = (produit.id == StoreIDs.plusAnnual) ? .annual : .lifetime
        return StoreProduct(id: produit.id, kind: kind, displayName: produit.displayName,
                            displayPrice: produit.displayPrice, offreIntro: libelléIntro(produit))
    }

    private func classement(_ k: ProductKind) -> Int { k == .annual ? 0 : 1 }

    /// Libellé de l'offre d'introduction gratuite d'un abonnement (« Essai gratuit : 1 semaine »),
    /// nil si le produit n'a pas d'essai gratuit. Composé au runtime → `String(localized:)`,
    /// sinon la ligne de prix du paywall fuiterait en français dans les 7 langues.
    private func libelléIntro(_ produit: Product) -> String? {
        guard let offre = produit.subscription?.introductoryOffer,
              offre.paymentMode == .freeTrial else { return nil }
        let période = offre.period
        let n = période.value
        let unité: String
        switch période.unit {
        case .day: unité = String(localized: n > 1 ? "jours" : "jour")
        case .week: unité = String(localized: n > 1 ? "semaines" : "semaine")
        case .month: unité = String(localized: "mois")
        case .year: unité = String(localized: n > 1 ? "ans" : "an")
        @unknown default: unité = String(localized: "jours")
        }
        return String(localized: "Essai gratuit : \(n) \(unité)")
    }
}
