# Mode premium Wello+ — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ajouter un mode premium « Wello+ » (achat unique lifetime, StoreKit 2) qui débloque l'historique illimité, avec toute la plomberie de gating/paywall en place pour les futures features payantes.

**Architecture:** Logique de gating pure et testée dans `WelloKit` ; service StoreKit derrière un protocole + mock ; `EntitlementStore` `@Observable` injecté via `.environment` comme `HydrationStore` ; gating dans les vues (historique borné à 7 jours en gratuit + carte de teasing) ; paywall en `.sheet`.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, StoreKit 2, Swift Testing (`swift test`). Patterns existants : services derrière protocoles + mocks, store `@Observable`, pattern MV.

**Note de vérification :** la commande de type-check du `CLAUDE.md` utilise des globs (`WelloKit/Sources/WelloKit/*.swift`, `Wello/Wello/Services/*.swift`, `Wello/Wello/Views/*.swift`, `App/*.swift`) → **les nouveaux fichiers sont pris en compte automatiquement, aucune modification du `CLAUDE.md` n'est nécessaire.** Les blocs « type-check iOS » ci-dessous renvoient à cette commande complète :

```bash
# Depuis la racine du repo — recompile le module WelloKit puis type-check l'app iOS.
rm -rf /tmp/wellomod && mkdir -p /tmp/wellomod
xcrun --sdk iphonesimulator swiftc -emit-module -module-name WelloKit \
  -target arm64-apple-ios17.0-simulator \
  WelloKit/Sources/WelloKit/*.swift WelloKit/Sources/WelloKit/Models/*.swift \
  -emit-module-path /tmp/wellomod/WelloKit.swiftmodule
xcrun --sdk iphonesimulator swiftc -typecheck -D DEBUG \
  -target arm64-apple-ios17.0-simulator -I /tmp/wellomod \
  Wello/Wello/App/*.swift Wello/Wello/Models/*.swift \
  Wello/Wello/Services/*.swift Wello/Wello/Views/*.swift
```

---

## File Structure

**Créés :**
- `WelloKit/Sources/WelloKit/Premium.swift` — `PremiumFeature`, `EntitlementStatus`, `Entitlements`, `historyVisibleSince`. Logique pure de gating.
- `WelloKit/Tests/WelloKitTests/PremiumTests.swift` — tests de la logique de gating.
- `Wello/Wello/Services/StoreService.swift` — `StoreProduct`, `PurchaseOutcome`, `StoreServicing`, `StoreKitService` (réel).
- `Wello/Wello/Services/EntitlementStore.swift` — `EntitlementStore` `@Observable`.
- `Wello/Wello/Views/PaywallView.swift` — `PaywallView` + `PremiumGateCard` (teasing réutilisable).

**Modifiés :**
- `Wello/Wello/Services/Mocks.swift` — ajout `MockStoreService`.
- `Wello/Wello/App/WelloApp.swift` — crée/injecte `EntitlementStore`, démarre l'écoute des transactions.
- `Wello/Wello/Views/ProfileView.swift` — ligne « Wello+ » → paywall.
- `Wello/Wello/Views/HistoryView.swift` — historique borné à 7 jours en gratuit + carte de teasing.
- `Wello/Wello/Views/PreviewSupport.swift` — helper `entitlements(_:)` pour les previews.

---

## Task 1 : Logique de gating pure (WelloKit)

**Files:**
- Create: `WelloKit/Sources/WelloKit/Premium.swift`
- Test: `WelloKit/Tests/WelloKitTests/PremiumTests.swift`

- [ ] **Step 1 : Écrire les tests qui échouent**

Create `WelloKit/Tests/WelloKitTests/PremiumTests.swift` :

```swift
import Testing
import Foundation
@testable import WelloKit

@Suite("Premium")
struct PremiumTests {

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    @Test("free ne déverrouille aucune feature premium")
    func freeVerrouille() {
        let e = Entitlements(status: .free)
        for f in PremiumFeature.allCases {
            #expect(e.isUnlocked(f) == false)
        }
    }

    @Test("plus déverrouille toutes les features")
    func plusDéverrouille() {
        let e = Entitlements(status: .plus)
        for f in PremiumFeature.allCases {
            #expect(e.isUnlocked(f) == true)
        }
    }

    @Test("historyVisibleSince : plus = illimité (nil)")
    func historiquePlus() {
        #expect(historyVisibleSince(status: .plus, now: .now, calendar: utc) == nil)
    }

    @Test("historyVisibleSince : free = début du jour 6 jours avant aujourd'hui (7 jours inclus)")
    func historiqueFree() {
        let now = utc.date(from: DateComponents(year: 2026, month: 6, day: 4, hour: 15, minute: 30))!
        let attendu = utc.date(from: DateComponents(year: 2026, month: 5, day: 29, hour: 0, minute: 0))!
        #expect(historyVisibleSince(status: .free, now: now, calendar: utc) == attendu)
    }
}
```

- [ ] **Step 2 : Lancer les tests pour vérifier l'échec**

Run: `cd WelloKit && swift test --filter Premium`
Expected: FAIL — `cannot find 'Entitlements' / 'PremiumFeature' / 'historyVisibleSince' in scope`.

- [ ] **Step 3 : Écrire l'implémentation minimale**

Create `WelloKit/Sources/WelloKit/Premium.swift` :

```swift
import Foundation

/// Features pouvant être réservées à Wello+. Couvre dès maintenant tout le périmètre prévu
/// pour que chaque feature ultérieure n'ait qu'à brancher son gating, sans toucher l'infra.
public enum PremiumFeature: String, Sendable, CaseIterable {
    case unlimitedHistory
    case analytics
    case customDrinks
    case advancedTuning
    case export
    case themes
    case adaptiveReminders
    case widget
}

/// Palier d'accès de l'utilisateur.
public enum EntitlementStatus: Sendable, Equatable {
    case free
    case plus
}

/// Table palier → features, en un seul endroit testable.
/// Le cœur gratuit (calcul, saisie, jauge, historique 7 j) n'est pas une `PremiumFeature`.
public struct Entitlements: Sendable {
    public let status: EntitlementStatus

    public init(status: EntitlementStatus) {
        self.status = status
    }

    public func isUnlocked(_ feature: PremiumFeature) -> Bool {
        switch status {
        case .plus: return true
        case .free: return false
        }
    }
}

/// Borne basse de l'historique visible. `nil` = illimité (Wello+).
/// En gratuit : début du jour 6 jours avant aujourd'hui → 7 jours calendaires inclus.
public func historyVisibleSince(status: EntitlementStatus,
                                now: Date,
                                calendar: Calendar = .current) -> Date? {
    switch status {
    case .plus:
        return nil
    case .free:
        let débutAujourdhui = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -6, to: débutAujourdhui)
    }
}
```

- [ ] **Step 4 : Lancer les tests pour vérifier le succès**

Run: `cd WelloKit && swift test --filter Premium`
Expected: PASS (4 tests).

- [ ] **Step 5 : Commit**

```bash
git add WelloKit/Sources/WelloKit/Premium.swift WelloKit/Tests/WelloKitTests/PremiumTests.swift
git commit -m "feat(premium): logique de gating pure (WelloKit)"
```

---

## Task 2 : Protocole StoreServicing + mock

**Files:**
- Create: `Wello/Wello/Services/StoreService.swift`
- Modify: `Wello/Wello/Services/Mocks.swift`

- [ ] **Step 1 : Créer les types et le protocole**

Create `Wello/Wello/Services/StoreService.swift` (la partie protocole + types ; l'impl réelle vient en Task 3 dans le même fichier) :

```swift
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
```

- [ ] **Step 2 : Ajouter le mock**

Modify `Wello/Wello/Services/Mocks.swift` — ajouter à la fin du fichier (après `MockNotificationService`) :

```swift
struct MockStoreService: StoreServicing {
    var statut: EntitlementStatus = .free
    func statutActuel() async -> EntitlementStatus { statut }
    func produitPlus() async -> StoreProduct? {
        StoreProduct(displayName: "Wello+", displayPrice: "8,99 €")
    }
    func acheter() async throws -> PurchaseOutcome { .success }
    func restaurer() async -> EntitlementStatus { statut }
    func observerTransactions() -> AsyncStream<EntitlementStatus> {
        AsyncStream { $0.finish() }
    }
}
```

Et ajouter en haut de `Mocks.swift`, sous `import WelloKit`, rien de plus n'est requis (`EntitlementStatus` vient déjà de `WelloKit`).

- [ ] **Step 3 : Type-check iOS**

Run la commande de type-check complète (voir en-tête du plan).
Expected: 0 erreur. (`StoreKitService` n'existe pas encore mais n'est référencé nulle part — OK.)

- [ ] **Step 4 : Commit**

```bash
git add Wello/Wello/Services/StoreService.swift Wello/Wello/Services/Mocks.swift
git commit -m "feat(premium): protocole StoreServicing + MockStoreService"
```

---

## Task 3 : Implémentation StoreKit réelle

**Files:**
- Modify: `Wello/Wello/Services/StoreService.swift`

- [ ] **Step 1 : Ajouter `StoreKitService`**

Modify `Wello/Wello/Services/StoreService.swift`.

D'abord, **réintroduire `import StoreKit`** en haut du fichier (retiré en Task 2 car alors inutilisé) — les imports doivent être `import Foundation` / `import StoreKit` / `import WelloKit`.

Puis ajouter à la fin du fichier :

```swift
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
                    switch result {
                    case .verified(let t):
                        await t.finish()
                        continuation.yield(t.revocationDate == nil ? .plus : .free)
                    case .unverified(let t, _):
                        await t.finish()   // vide la file ; pas d'accès sur transaction non vérifiée
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
```

- [ ] **Step 2 : Type-check iOS**

Run la commande de type-check complète.
Expected: 0 erreur (les symboles StoreKit `Transaction`, `Product`, `AppStore` se résolvent via le SDK simulateur).

- [ ] **Step 3 : Commit**

```bash
git add Wello/Wello/Services/StoreService.swift
git commit -m "feat(premium): StoreKitService (StoreKit 2)"
```

---

## Task 4 : EntitlementStore

**Files:**
- Create: `Wello/Wello/Services/EntitlementStore.swift`

- [ ] **Step 1 : Créer le store observable**

Create `Wello/Wello/Services/EntitlementStore.swift` :

```swift
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
    private var démarré = false

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
    /// Idempotent : le drapeau est posé avant le premier `await` (l'isolation @MainActor sérialise
    /// le préfixe synchrone), donc même deux appels concurrents ne lancent qu'une seule écoute.
    func démarrer() async {
        guard !démarré else { return }
        démarré = true
        appliquer(await store.statutActuel())
        updatesTask = Task { [weak self] in
            guard let self else { return }
            let stream = self.store.observerTransactions()
            for await nouveau in stream {
                self.appliquer(nouveau)
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
```

- [ ] **Step 2 : Type-check iOS**

Run la commande de type-check complète.
Expected: 0 erreur.

- [ ] **Step 3 : Commit**

```bash
git add Wello/Wello/Services/EntitlementStore.swift
git commit -m "feat(premium): EntitlementStore observable + cache offline"
```

---

## Task 5 : Câbler EntitlementStore dans l'app

**Files:**
- Modify: `Wello/Wello/App/WelloApp.swift`
- Modify: `Wello/Wello/Views/PreviewSupport.swift`

- [ ] **Step 1 : Injecter le store dans WelloApp**

Modify `Wello/Wello/App/WelloApp.swift`.

Ajouter la propriété d'état après `@State private var store: HydrationStore` (ligne 9) :

```swift
    @State private var entitlements: EntitlementStore
```

Dans `init()`, après le bloc qui crée `store` (après `_store = State(initialValue: store)`, ligne 24), ajouter :

```swift
        _entitlements = State(initialValue: EntitlementStore(store: StoreKitService()))
```

Dans `body`, remplacer le bloc `RootView()` existant :

```swift
            RootView()
                .environment(\.locale, Locale(identifier: "fr_FR"))   // app francophone : dates/nombres en FR
                .environment(store)
```

par :

```swift
            RootView()
                .environment(\.locale, Locale(identifier: "fr_FR"))   // app francophone : dates/nombres en FR
                .environment(store)
                .environment(entitlements)
                .task { await entitlements.démarrer() }
```

- [ ] **Step 2 : Ajouter le helper de preview**

Modify `Wello/Wello/Views/PreviewSupport.swift`.

Ajouter `import WelloKit` sous `import SwiftData` :

```swift
import SwiftData
import WelloKit
```

Ajouter cette méthode dans l'enum `PreviewSupport`, après `store(_:)` :

```swift
    /// EntitlementStore sur mock, pour prévisualiser l'UI premium (free par défaut).
    static func entitlements(_ statut: EntitlementStatus = .free) -> EntitlementStore {
        EntitlementStore(store: MockStoreService(statut: statut))
    }
```

- [ ] **Step 3 : Type-check iOS**

Run la commande de type-check complète.
Expected: 0 erreur.

- [ ] **Step 4 : Commit**

```bash
git add Wello/Wello/App/WelloApp.swift Wello/Wello/Views/PreviewSupport.swift
git commit -m "feat(premium): injection EntitlementStore + helper preview"
```

---

## Task 6 : PaywallView + carte de teasing

**Files:**
- Create: `Wello/Wello/Views/PaywallView.swift`

- [ ] **Step 1 : Créer le paywall et le composant de teasing**

Create `Wello/Wello/Views/PaywallView.swift` :

```swift
import SwiftUI
import WelloKit

/// Liens légaux requis par l'App Store pour un achat. À remplacer par les vraies URLs.
/// Force-unwrap sûr : ce sont des constantes ASCII valides (jamais issues d'une saisie).
enum WelloLinks {
    static let conditions = URL(string: "https://wello.app/conditions")!
    static let confidentialité = URL(string: "https://wello.app/confidentialite")!
}

/// Carte de teasing réutilisable (gating contextuel) : invite à passer Wello+.
struct PremiumGateCard: View {
    let bénéfice: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CardContainer {
                HStack(spacing: 14) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(WelloTheme.accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(bénéfice)
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(WelloTheme.ink)
                        Text("Débloquer avec Wello+")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(WelloTheme.inkSoft)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WelloTheme.inkSoft.opacity(0.6))
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(bénéfice). Débloquer avec Wello+")
        .accessibilityHint("Ouvre l'offre Wello+")
    }
}

/// Paywall Wello+ : achat unique « lifetime ».
struct PaywallView: View {
    /// Bénéfice mis en avant selon le point d'entrée.
    var bénéfice: String = "Débloque toutes les fonctionnalités"

    @Environment(EntitlementStore.self) private var entitlements
    @Environment(\.dismiss) private var dismiss

    @State private var produit: StoreProduct?
    @State private var enCours = false
    @State private var messageErreur: String?

    private static let avantages: [(icon: String, titre: String)] = [
        ("clock.arrow.circlepath", "Historique illimité"),
        ("chart.line.uptrend.xyaxis", "Analyses et tendances"),
        ("cup.and.saucer.fill", "Boissons personnalisées"),
        ("square.and.arrow.up", "Export CSV / PDF"),
        ("paintbrush.fill", "Thèmes et icônes"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    enTête
                    listeAvantages
                    if let messageErreur {
                        Text(messageErreur)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                    boutonAchat
                    boutonRestaurer
                    liensLégaux
                }
                .padding()
            }
            .welloBackground()
            .navigationTitle("Wello+")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
            .task { produit = await entitlements.produit() }
        }
    }

    private var enTête: some View {
        VStack(spacing: 8) {
            Image(systemName: "star.fill")
                .font(.system(size: 40))
                .foregroundStyle(WelloTheme.accentGradient)
                .accessibilityHidden(true)
            Text(bénéfice)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(WelloTheme.ink)
                .multilineTextAlignment(.center)
            Text("Un seul paiement, à vie.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(WelloTheme.inkSoft)
        }
    }

    private var listeAvantages: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Self.avantages, id: \.titre) { a in
                    HStack(spacing: 12) {
                        Image(systemName: a.icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(WelloTheme.accent)
                            .frame(width: 28)
                        Text(a.titre)
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(WelloTheme.ink)
                        Spacer()
                    }
                }
            }
        }
    }

    private var boutonAchat: some View {
        Button {
            Task { await acheter() }
        } label: {
            Group {
                if enCours {
                    ProgressView().tint(.white)
                } else {
                    Text(produit.map { "Débloquer — \($0.displayPrice)" } ?? "Débloquer")
                        .font(.system(.headline, design: .rounded))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(WelloTheme.accentGradient,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(enCours)
        .accessibilityLabel(produit.map { "Débloquer Wello+ pour \($0.displayPrice)" } ?? "Débloquer Wello+")
    }

    private var boutonRestaurer: some View {
        Button("Restaurer mes achats") {
            Task { await restaurer() }
        }
        .font(.system(.subheadline, design: .rounded))
        .frame(minHeight: 44)
        .foregroundStyle(WelloTheme.accentDeep)
        .disabled(enCours)
    }

    private var liensLégaux: some View {
        HStack(spacing: 18) {
            Link("Conditions d'utilisation", destination: WelloLinks.conditions)
            Link("Confidentialité", destination: WelloLinks.confidentialité)
        }
        .font(.system(.caption, design: .rounded))
        .foregroundStyle(WelloTheme.inkSoft)
    }

    private func acheter() async {
        enCours = true
        messageErreur = nil
        defer { enCours = false }
        do {
            switch try await entitlements.acheterPlus() {
            case .success: dismiss()
            case .userCancelled: break
            case .pending: messageErreur = "Achat en attente de validation."
            }
        } catch {
            messageErreur = "L'achat a échoué. Réessaie plus tard."
        }
    }

    private func restaurer() async {
        enCours = true
        messageErreur = nil
        defer { enCours = false }
        await entitlements.restaurer()
        if entitlements.isUnlocked(.unlimitedHistory) {
            dismiss()
        } else {
            messageErreur = "Aucun achat à restaurer."
        }
    }
}

#if DEBUG
#Preview("Paywall") {
    PaywallView(bénéfice: "Garde tout ton historique")
        .environment(PreviewSupport.entitlements(.free))
}
#endif
```

- [ ] **Step 2 : Type-check iOS**

Run la commande de type-check complète.
Expected: 0 erreur.

- [ ] **Step 3 : Commit**

```bash
git add Wello/Wello/Views/PaywallView.swift
git commit -m "feat(premium): PaywallView + carte de teasing réutilisable"
```

---

## Task 7 : Point d'entrée « Wello+ » dans le Profil

**Files:**
- Modify: `Wello/Wello/Views/ProfileView.swift`

- [ ] **Step 1 : Ajouter l'état premium**

Modify `Wello/Wello/Views/ProfileView.swift`.

Après `@Query private var profils: [UserProfile]`, ajouter :

```swift
    @Environment(EntitlementStore.self) private var entitlements
    @State private var paywall = false
```

- [ ] **Step 2 : Ajouter la section Wello+ en haut du Form**

Dans `body`, juste après l'ouverture `Form {` et avant `if let profil {`, insérer :

```swift
                Section {
                    Button {
                        paywall = true
                    } label: {
                        HStack {
                            // value = nil → `label` n'insère pas de Spacer interne ; on gère le trailing nous-mêmes.
                            label("Wello+", nil, icon: "star.fill", teinte: .yellow)
                            Spacer()
                            if entitlements.isUnlocked(.unlimitedHistory) {
                                Text("Actif")
                                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                    .foregroundStyle(.green)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                            } else {
                                Text("Débloquer tout")
                                    .font(.system(.subheadline, design: .rounded))
                                    .foregroundStyle(WelloTheme.inkSoft)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(WelloTheme.inkSoft.opacity(0.6))
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .disabled(entitlements.isUnlocked(.unlimitedHistory))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(entitlements.isUnlocked(.unlimitedHistory) ? "Wello+, actif" : "Wello+, débloquer tout")
                    .accessibilityHint(entitlements.isUnlocked(.unlimitedHistory) ? "" : "Ouvre l'offre Wello+")
                }
```

- [ ] **Step 3 : Présenter le paywall**

Sur le `Form` (à côté de `.scrollContentBackground(.hidden)` / `.welloBackground()` / `.navigationTitle("Profil")`), ajouter le modifier :

```swift
            .sheet(isPresented: $paywall) { PaywallView() }
```

- [ ] **Step 4 : Mettre à jour la preview**

Remplacer le bloc `#Preview` en bas de `ProfileView.swift` :

```swift
#if DEBUG
#Preview {
    let container = PreviewSupport.container()
    return ProfileView()
        .modelContainer(container)
        .environment(PreviewSupport.store(container))
}
#endif
```

par :

```swift
#if DEBUG
#Preview {
    let container = PreviewSupport.container()
    return ProfileView()
        .modelContainer(container)
        .environment(PreviewSupport.store(container))
        .environment(PreviewSupport.entitlements(.free))
}
#endif
```

- [ ] **Step 5 : Type-check iOS**

Run la commande de type-check complète.
Expected: 0 erreur.

- [ ] **Step 6 : Commit**

```bash
git add Wello/Wello/Views/ProfileView.swift
git commit -m "feat(premium): point d'entrée Wello+ dans le Profil"
```

---

## Task 8 : Gating de l'historique (feature phare)

**Files:**
- Modify: `Wello/Wello/Views/HistoryView.swift`

- [ ] **Step 1 : Ajouter l'état premium et l'horizon visible**

Modify `Wello/Wello/Views/HistoryView.swift`.

Après `@State private var plage = 7`, ajouter :

```swift
    @Environment(EntitlementStore.self) private var entitlements
    @State private var paywall = false
```

Ajouter ces deux propriétés calculées dans la struct (par ex. juste après `body`) :

```swift
    /// Borne basse de l'historique selon le palier (nil = illimité).
    private var horizon: Date? {
        historyVisibleSince(status: entitlements.status, now: .now)
    }

    /// Objectifs réellement affichables au palier courant.
    private var objectifsVisibles: [DailyGoal] {
        guard let horizon else { return objectifs }
        return objectifs.filter { $0.date >= horizon }
    }
```

- [ ] **Step 2 : Borner le contenu aux objectifs visibles + carte de teasing**

Remplacer la propriété `contenu` existante :

```swift
    private var contenu: some View {
        let conso = consommationParJour()
        return ScrollView {
            LazyVStack(spacing: 16) {
                sélecteurPlage
                grapheCard(conso)
                statsCard(conso)
                ForEach(objectifs) { goal in
                    NavigationLink {
                        DayDetailView(date: goal.date)
                    } label: {
                        carteJour(goal, conso: conso)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
    }
```

par :

```swift
    private var contenu: some View {
        let conso = consommationParJour()
        let premium = entitlements.isUnlocked(.unlimitedHistory)
        return ScrollView {
            LazyVStack(spacing: 16) {
                if premium { sélecteurPlage }
                grapheCard(conso)
                statsCard(conso)
                ForEach(objectifsVisibles) { goal in
                    NavigationLink {
                        DayDetailView(date: goal.date)
                    } label: {
                        carteJour(goal, conso: conso)
                    }
                    .buttonStyle(.plain)
                }
                if !premium && objectifs.count > objectifsVisibles.count {
                    PremiumGateCard(bénéfice: "Historique complet et illimité") {
                        paywall = true
                    }
                }
            }
            .padding()
        }
    }
```

- [ ] **Step 3 : Brancher graphe et stats sur les objectifs visibles**

Dans `barres(_:)`, remplacer `objectifs.prefix(plage)` par `objectifsVisibles.prefix(plage)` :

```swift
    private func barres(_ conso: [Date: Int]) -> [JourBarre] {
        objectifsVisibles.prefix(plage).map {
            JourBarre(id: $0.date, date: $0.date, consommé: consommé(conso, pour: $0.date), objectif: $0.totalML)
        }
        .reversed()   // chronologique pour l'axe X
    }
```

Dans `totals(_:)`, remplacer `objectifs.map` par `objectifsVisibles.map` :

```swift
    private func totals(_ conso: [Date: Int]) -> [DailyTotal] {
        objectifsVisibles.map { DailyTotal(consumedML: consommé(conso, pour: $0.date), goalML: $0.totalML) }
    }
```

Dans `série(_:)`, remplacer `objectifs.map` par `objectifsVisibles.map` :

```swift
    private func série(_ conso: [Date: Int]) -> Int {
        var liste = objectifsVisibles.map { (date: $0.date,
                                     total: DailyTotal(consumedML: consommé(conso, pour: $0.date), goalML: $0.totalML)) }
        // Un « aujourd'hui » encore en cours ne casse pas la série.
        if let premier = liste.first, !premier.total.reached, Calendar.current.isDateInToday(premier.date) {
            liste.removeFirst()
        }
        return HydrationStats.currentStreak(liste.map(\.total))
    }
```

- [ ] **Step 4 : Présenter le paywall**

Sur le `Group { ... }` du `body` (à côté de `.welloBackground()` / `.navigationTitle("Historique")`), ajouter :

```swift
            .sheet(isPresented: $paywall) {
                PaywallView(bénéfice: "Garde tout ton historique")
            }
```

- [ ] **Step 5 : Mettre à jour la preview**

Remplacer le `#Preview` en bas de `HistoryView.swift` :

```swift
#if DEBUG
#Preview {
    HistoryView()
        .modelContainer(PreviewSupport.container())
}
#endif
```

par :

```swift
#if DEBUG
#Preview("Gratuit") {
    HistoryView()
        .modelContainer(PreviewSupport.container())
        .environment(PreviewSupport.entitlements(.free))
}

#Preview("Wello+") {
    HistoryView()
        .modelContainer(PreviewSupport.container())
        .environment(PreviewSupport.entitlements(.plus))
}
#endif
```

- [ ] **Step 6 : Type-check iOS**

Run la commande de type-check complète.
Expected: 0 erreur.

- [ ] **Step 7 : Commit**

```bash
git add Wello/Wello/Views/HistoryView.swift
git commit -m "feat(premium): historique borné à 7 jours en gratuit + teasing Wello+"
```

---

## Vérification finale

- [ ] **Logique pure :** `cd WelloKit && swift test` → tout passe (dont la suite `Premium`).
- [ ] **App iOS :** la commande de type-check complète → 0 erreur.
- [ ] **Previews (dans Xcode, manuel) :** `HistoryView` « Gratuit » montre 7 jours + carte de teasing ; « Wello+ » montre tout + sélecteur 7/30 ; `PaywallView` affiche le prix mock ; ligne « Wello+ » visible dans le Profil.

## Étapes Xcode / App Store Connect (manuelles, hors CLI)

- Capability **In-App Purchase** sur le target `Wello`.
- Produit non-consommable `com.wello.plus.lifetime` dans App Store Connect.
- Fichier de configuration local `Wello.storekit` + activé dans le scheme (test achat/restauration/annulation/offline).
- Remplacer les URLs `WelloLinks.conditions` / `.confidentialité` par les vraies pages légales.
