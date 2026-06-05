# Boissons personnalisées (Wello+) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ajouter les boissons personnalisées Wello+ : chaque type de boisson porte un coefficient d'hydratation, et l'hydratation *effective* (`volume × coefficient`) compte vers l'objectif — l'eau (coeff 1.0) restant le geste gratuit inchangé.

**Architecture:** Logique pure et testée dans `WelloKit` (`DrinkType`, `effectiveHydrationML`, `resolveCoefficient`, `clampedDayTotal`) ; coefficients édités persistés dans un store `DrinkCatalog` `@Observable` injecté via `.environment` ; `HydrationLog` gagne `drinkType` + `coefficient` (snapshot) ; le « consommé » devient une somme d'effectifs bornée à ≥ 0 ; saisie typée via la feuille « Autre » (gating premium), édition des coefficients au Profil.

**Tech Stack:** Swift 6, SwiftUI, SwiftData (migration légère), Swift Testing (`swift test`). Patterns existants : logique pure dans `WelloKit`, store `@Observable` injecté, gating via `EntitlementStore.isUnlocked(_:)`.

**Note de vérification :** les globs de la commande de type-check du `CLAUDE.md` (`WelloKit/Sources/WelloKit/*.swift`, `Wello/Wello/Services/*.swift`, `Wello/Wello/Views/*.swift`, `App/*.swift`) prennent en compte les nouveaux fichiers automatiquement. La commande complète (référencée plus bas par « type-check iOS ») :

```bash
# Depuis la racine du repo — recompile le module WelloKit puis type-check l'app iOS.
rm -rf /tmp/wellomod && mkdir -p /tmp/wellomod
xcrun --sdk iphonesimulator swiftc -emit-module -module-name WelloKit \
  -target arm64-apple-ios17.0-simulator \
  WelloKit/Sources/WelloKit/*.swift WelloKit/Sources/WelloKit/Models/*.swift \
  -emit-module-path /tmp/wellomod/WelloKit.swiftmodule
xcrun --sdk iphonesimulator swiftc -typecheck -D DEBUG \
  -enable-upcoming-feature MemberImportVisibility \
  -target arm64-apple-ios17.0-simulator -I /tmp/wellomod \
  Wello/Wello/App/*.swift Wello/Wello/Models/*.swift \
  Wello/Wello/Services/*.swift Wello/Wello/Views/*.swift
```

---

## File Structure

**Créés :**
- `WelloKit/Sources/WelloKit/Drink.swift` — `DrinkType` (catalogue), `effectiveHydrationML`, `resolveCoefficient`, `clampedDayTotal`, `coefficientRange`. Logique pure.
- `WelloKit/Tests/WelloKitTests/DrinkTests.swift` — tests de la logique pure.
- `Wello/Wello/Services/DrinkCatalog.swift` — store `@Observable` des coefficients (défauts + overrides UserDefaults).

**Modifiés :**
- `Wello/Wello/Models/HydrationLog.swift` — champs `drinkType` + `coefficient` + computed `drink` / `effectiveML`.
- `Wello/Wello/Services/HydrationStore.swift` — `log(ml:drink:coefficient:)`, consommé = effectif borné, suppressions HealthKit symétriques.
- `Wello/Wello/App/WelloApp.swift` — crée/injecte `DrinkCatalog`.
- `Wello/Wello/Views/PreviewSupport.swift` — helper `drinkCatalog()` + une prise « café » d'exemple.
- `Wello/Wello/Views/MainView.swift` — feuille de saisie typée (premium) vs eau-seule + teasing (gratuit).
- `Wello/Wello/Views/DayDetailView.swift` — icône/nom de boisson + effectif par prise, total effectif.
- `Wello/Wello/Views/HistoryView.swift` — consommation par jour = effectif borné.
- `Wello/Wello/Views/ProfileView.swift` — section « Boissons » (édition des coefficients, gating).

---

## Task 1 : Logique pure des boissons (WelloKit)

**Files:**
- Create: `WelloKit/Sources/WelloKit/Drink.swift`
- Test: `WelloKit/Tests/WelloKitTests/DrinkTests.swift`

- [ ] **Step 1 : Écrire les tests qui échouent**

Create `WelloKit/Tests/WelloKitTests/DrinkTests.swift` :

```swift
import Testing
@testable import WelloKit

@Suite("Drink")
struct DrinkTests {

    @Test("eau est le 1ᵉʳ cas et a un coefficient de 1.0")
    func eauDéfaut() {
        #expect(DrinkType.allCases.first == .water)
        #expect(DrinkType.water.defaultCoefficient == 1.0)
    }

    @Test("chaque boisson a un coefficient par défaut dans les bornes")
    func défautsDansBornes() {
        for d in DrinkType.allCases {
            #expect(coefficientRange.contains(d.defaultCoefficient))
        }
    }

    @Test("effectiveHydrationML : eau = identité")
    func eauIdentité() {
        #expect(effectiveHydrationML(volumeML: 500, coefficient: 1.0) == 500)
    }

    @Test("effectiveHydrationML : café 250 × 0.8 = 200")
    func caféEffectif() {
        #expect(effectiveHydrationML(volumeML: 250, coefficient: 0.8) == 200)
    }

    @Test("effectiveHydrationML : spiritueux peut être négatif")
    func spiritueuxNégatif() {
        #expect(effectiveHydrationML(volumeML: 100, coefficient: -0.5) == -50)
    }

    @Test("effectiveHydrationML : arrondi au plus proche")
    func arrondi() {
        #expect(effectiveHydrationML(volumeML: 333, coefficient: 0.9) == 300)   // 299.7 → 300
    }

    @Test("resolveCoefficient : override respecté")
    func overrideRespecté() {
        #expect(resolveCoefficient(default: 0.8, override: 0.95) == 0.95)
    }

    @Test("resolveCoefficient : défaut si pas d'override")
    func défautSiNil() {
        #expect(resolveCoefficient(default: 0.8, override: nil) == 0.8)
    }

    @Test("resolveCoefficient : borné à [-1.0 … 1.5]")
    func bornes() {
        #expect(resolveCoefficient(default: 1.0, override: 9.0) == 1.5)
        #expect(resolveCoefficient(default: 1.0, override: -9.0) == -1.0)
    }

    @Test("clampedDayTotal : négatif → 0, positif inchangé")
    func clamp() {
        #expect(clampedDayTotal(-200) == 0)
        #expect(clampedDayTotal(1500) == 1500)
    }
}
```

- [ ] **Step 2 : Lancer les tests pour vérifier l'échec**

Run: `cd WelloKit && swift test --filter Drink`
Expected: FAIL — `cannot find 'DrinkType' / 'effectiveHydrationML' / 'resolveCoefficient' / 'clampedDayTotal' / 'coefficientRange' in scope`.

- [ ] **Step 3 : Écrire l'implémentation**

Create `WelloKit/Sources/WelloKit/Drink.swift` :

```swift
import Foundation

/// Type de boisson loggable. Chaque cas porte un coefficient d'hydratation de référence
/// (heuristique, éditable côté app). `water` est toujours le 1ᵉʳ cas (défaut).
public enum DrinkType: String, Sendable, CaseIterable {
    case water, sparkling, herbalTea, milk, tea, coffee, juice, soda, energy, beer, wine, spirits

    /// Libellé FR affichable.
    public var label: String {
        switch self {
        case .water: return "Eau"
        case .sparkling: return "Eau gazeuse"
        case .herbalTea: return "Tisane"
        case .milk: return "Lait"
        case .tea: return "Thé"
        case .coffee: return "Café"
        case .juice: return "Jus de fruits"
        case .soda: return "Soda"
        case .energy: return "Boisson énergisante"
        case .beer: return "Bière"
        case .wine: return "Vin"
        case .spirits: return "Spiritueux"
        }
    }

    /// SF Symbol (iOS 17+). Repli neutre acceptable si un symbole manquait à l'exécution.
    public var icon: String {
        switch self {
        case .water: return "drop.fill"
        case .sparkling: return "bubbles.and.sparkles"
        case .herbalTea: return "leaf.fill"
        case .milk, .tea, .coffee: return "cup.and.saucer.fill"
        case .juice, .soda: return "waterbottle.fill"
        case .energy: return "bolt.fill"
        case .beer: return "mug.fill"
        case .wine, .spirits: return "wineglass.fill"
        }
    }

    /// Coefficient d'hydratation de référence (valeur indicative, non médicale).
    public var defaultCoefficient: Double {
        switch self {
        case .water, .sparkling, .herbalTea, .milk: return 1.0
        case .tea: return 0.9
        case .coffee: return 0.8
        case .juice, .soda: return 0.85
        case .energy: return 0.7
        case .beer: return 0.5
        case .wine: return 0.0
        case .spirits: return -0.5
        }
    }
}

/// Bornes d'un coefficient d'hydratation éditable.
public let coefficientRange: ClosedRange<Double> = -1.0...1.5

/// Hydratation effective (ml) d'une prise : `volume × coefficient`, arrondi au plus proche.
/// Peut être négatif (boisson déshydratante).
public func effectiveHydrationML(volumeML: Int, coefficient: Double) -> Int {
    Int((Double(volumeML) * coefficient).rounded())
}

/// Coefficient résolu : l'`override` s'il existe, sinon le `default`, borné à `coefficientRange`.
public func resolveCoefficient(default défaut: Double, override: Double?) -> Double {
    let valeur = override ?? défaut
    return min(max(valeur, coefficientRange.lowerBound), coefficientRange.upperBound)
}

/// « Consommé » affichable d'un jour : jamais négatif (l'alcool peut faire reculer la somme).
public func clampedDayTotal(_ sum: Int) -> Int {
    max(0, sum)
}
```

- [ ] **Step 4 : Lancer les tests pour vérifier le succès**

Run: `cd WelloKit && swift test --filter Drink`
Expected: PASS (10 tests).

- [ ] **Step 5 : Commit**

```bash
git add WelloKit/Sources/WelloKit/Drink.swift WelloKit/Tests/WelloKitTests/DrinkTests.swift
git commit -m "feat(kit): logique pure des boissons (coefficients d'hydratation)"
```

---

## Task 2 : Champs boisson sur HydrationLog

**Files:**
- Modify: `Wello/Wello/Models/HydrationLog.swift`

- [ ] **Step 1 : Ajouter les champs + computed**

Replace tout le contenu de `Wello/Wello/Models/HydrationLog.swift` par :

```swift
import Foundation
import SwiftData
import WelloKit

/// Une prise enregistrée (eau ou autre boisson).
@Model
final class HydrationLog {
    var amountML: Int
    var loggedAt: Date
    /// Provenance : "app" (saisie dans Wello) ou "healthkit" (importée).
    var source: String
    /// UUID de l'échantillon HealthKit d'origine, pour les prises importées (dédup).
    /// nil pour les prises saisies dans Wello.
    var healthKitUUID: UUID?
    /// Type de boisson (rawValue `DrinkType`). Défaut inline = migration légère SwiftData ;
    /// "water" pour les prises existantes et les imports HealthKit.
    var drinkType: String = "water"
    /// Coefficient d'hydratation snapshoté au moment de la prise. N'est jamais réécrit ensuite
    /// (éditer un coefficient au Profil ne modifie pas l'historique).
    var coefficient: Double = 1.0

    /// Boisson typée (repli sur l'eau si la valeur stockée est inconnue).
    var drink: DrinkType { DrinkType(rawValue: drinkType) ?? .water }

    /// Hydratation effective (ml) : `volume × coefficient`, arrondi. Peut être négatif.
    var effectiveML: Int { effectiveHydrationML(volumeML: amountML, coefficient: coefficient) }

    init(amountML: Int, loggedAt: Date = .now, source: String = "app",
         healthKitUUID: UUID? = nil,
         drinkType: String = "water", coefficient: Double = 1.0) {
        self.amountML = amountML
        self.loggedAt = loggedAt
        self.source = source
        self.healthKitUUID = healthKitUUID
        self.drinkType = drinkType
        self.coefficient = coefficient
    }
}
```

- [ ] **Step 2 : Type-check iOS**

Run la commande de type-check complète (voir en-tête).
Expected: 0 erreur.

- [ ] **Step 3 : Commit**

```bash
git add Wello/Wello/Models/HydrationLog.swift
git commit -m "feat(model): drinkType + coefficient + effectiveML sur HydrationLog"
```

---

## Task 3 : Store DrinkCatalog (coefficients édités)

**Files:**
- Create: `Wello/Wello/Services/DrinkCatalog.swift`

- [ ] **Step 1 : Créer le store**

Create `Wello/Wello/Services/DrinkCatalog.swift` :

```swift
import Foundation
import Observation
import WelloKit

/// Coefficients d'hydratation par boisson : défauts de `WelloKit` + overrides utilisateur
/// persistés en `UserDefaults`. Injecté via `.environment` (comme `EntitlementStore`).
/// L'édition est réservée à Wello+ ; la lecture sert aussi à snapshoter le coefficient au log.
@MainActor
@Observable
final class DrinkCatalog {
    private let defaults: UserDefaults
    /// Overrides en mémoire (rawValue → coefficient), miroir de `UserDefaults`.
    private var overrides: [String: Double]

    private static let key = "wello.drinks.coefficients"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.overrides = (defaults.dictionary(forKey: Self.key) as? [String: Double]) ?? [:]
    }

    /// Coefficient résolu (override éventuel sinon défaut), borné à `coefficientRange`.
    func coefficient(for drink: DrinkType) -> Double {
        resolveCoefficient(default: drink.defaultCoefficient, override: overrides[drink.rawValue])
    }

    /// Vrai si l'utilisateur a personnalisé ce coefficient.
    func isCustomized(_ drink: DrinkType) -> Bool {
        overrides[drink.rawValue] != nil
    }

    /// Définit un override (borné) et persiste.
    func setCoefficient(_ valeur: Double, for drink: DrinkType) {
        overrides[drink.rawValue] = resolveCoefficient(default: valeur, override: nil)
        persist()
    }

    /// Réinitialise au coefficient par défaut.
    func reset(_ drink: DrinkType) {
        overrides[drink.rawValue] = nil
        persist()
    }

    private func persist() {
        defaults.set(overrides, forKey: Self.key)
    }
}
```

- [ ] **Step 2 : Type-check iOS**

Run la commande de type-check complète.
Expected: 0 erreur.

- [ ] **Step 3 : Commit**

```bash
git add Wello/Wello/Services/DrinkCatalog.swift
git commit -m "feat(premium): DrinkCatalog (coefficients défauts + overrides persistés)"
```

---

## Task 4 : Câbler DrinkCatalog dans l'app + preview

**Files:**
- Modify: `Wello/Wello/App/WelloApp.swift`
- Modify: `Wello/Wello/Views/PreviewSupport.swift`

- [ ] **Step 1 : Injecter le store dans WelloApp**

Modify `Wello/Wello/App/WelloApp.swift`.

Après la ligne `@State private var entitlements: EntitlementStore` (ligne 10), ajouter :

```swift
    @State private var drinks: DrinkCatalog
```

Dans `init()`, après `_entitlements = State(initialValue: EntitlementStore(store: StoreKitService()))` (ligne 26), ajouter :

```swift
        _drinks = State(initialValue: DrinkCatalog())
```

Dans `body`, remplacer le bloc :

```swift
            RootView()
                .environment(\.locale, Locale(identifier: "fr_FR"))   // app francophone : dates/nombres en FR
                .environment(store)
                .environment(entitlements)
                .task { await entitlements.démarrer() }
```

par :

```swift
            RootView()
                .environment(\.locale, Locale(identifier: "fr_FR"))   // app francophone : dates/nombres en FR
                .environment(store)
                .environment(entitlements)
                .environment(drinks)
                .task { await entitlements.démarrer() }
```

- [ ] **Step 2 : Ajouter le helper de preview + une prise « café »**

Modify `Wello/Wello/Views/PreviewSupport.swift`.

Dans `container()`, après la ligne `ctx.insert(HydrationLog(amountML: 500))` (ligne 21), ajouter une prise typée pour les previews :

```swift
        ctx.insert(HydrationLog(amountML: 250, drinkType: "coffee", coefficient: 0.8))
```

Ajouter cette méthode dans l'enum `PreviewSupport`, après `entitlements(_:)` :

```swift
    /// Catalogue de boissons sur un domaine UserDefaults éphémère (previews isolées du réel).
    static func drinkCatalog() -> DrinkCatalog {
        DrinkCatalog(defaults: UserDefaults(suiteName: "preview.drinks") ?? .standard)
    }
```

- [ ] **Step 3 : Type-check iOS**

Run la commande de type-check complète.
Expected: 0 erreur.

- [ ] **Step 4 : Commit**

```bash
git add Wello/Wello/App/WelloApp.swift Wello/Wello/Views/PreviewSupport.swift
git commit -m "feat(premium): injection DrinkCatalog + helper preview"
```

---

## Task 5 : HydrationStore — log typé + consommé effectif

**Files:**
- Modify: `Wello/Wello/Services/HydrationStore.swift`

- [ ] **Step 1 : `log(ml:drink:coefficient:)` écrit l'effectif positif**

Modify `Wello/Wello/Services/HydrationStore.swift`.

Remplacer la méthode `log(ml:)` (lignes 198–207) :

```swift
    /// Enregistre une prise d'eau : SwiftData (source de vérité) + écriture HealthKit (Santé.app).
    func log(ml: Int) async {
        let entrée = HydrationLog(amountML: ml, loggedAt: .now, source: "app")
        modelContext.insert(entrée)
        await healthKit.écrireEau(ml: ml, date: .now)

        if let objectif = breakdown?.totalML {
            await notifications.planifierRappels(objectifML: objectif, consomméML: consomméAujourdhui())
        }
    }
```

par :

```swift
    /// Enregistre une prise (eau ou autre boisson) : SwiftData (source de vérité) + écriture
    /// HealthKit de l'hydratation effective positive (une boisson à effectif ≤ 0 n'écrit rien).
    func log(ml: Int, drink: DrinkType = .water, coefficient: Double = 1.0) async {
        let entrée = HydrationLog(amountML: ml, loggedAt: .now, source: "app",
                                  drinkType: drink.rawValue, coefficient: coefficient)
        modelContext.insert(entrée)
        let effectif = max(0, entrée.effectiveML)
        if effectif > 0 { await healthKit.écrireEau(ml: effectif, date: entrée.loggedAt) }

        if let objectif = breakdown?.totalML {
            await notifications.planifierRappels(objectifML: objectif, consomméML: consomméAujourdhui())
        }
    }
```

- [ ] **Step 2 : Suppressions HealthKit symétriques (effectif)**

Dans `annulerDernièrePrise()`, remplacer le bloc (lignes 220–223) :

```swift
        let ml = dernière.amountML
        let date = dernière.loggedAt
        modelContext.delete(dernière)
        await healthKit.supprimerEau(ml: ml, date: date)
```

par :

```swift
        let effectif = max(0, dernière.effectiveML)
        let date = dernière.loggedAt
        modelContext.delete(dernière)
        if effectif > 0 { await healthKit.supprimerEau(ml: effectif, date: date) }
```

Dans `supprimer(_:)`, remplacer le bloc (lignes 233–237) :

```swift
        let ml = log.amountML
        let date = log.loggedAt
        let estApp = log.source == "app"
        modelContext.delete(log)
        if estApp { await healthKit.supprimerEau(ml: ml, date: date) }
```

par :

```swift
        let effectif = max(0, log.effectiveML)
        let date = log.loggedAt
        let estApp = log.source == "app"
        modelContext.delete(log)
        if estApp && effectif > 0 { await healthKit.supprimerEau(ml: effectif, date: date) }
```

- [ ] **Step 3 : Consommé = somme des effectifs, bornée à ≥ 0**

Dans `consomméAujourdhui()`, remplacer la dernière ligne (ligne 250) :

```swift
        return logs.reduce(0) { $0 + $1.amountML }
```

par :

```swift
        return clampedDayTotal(logs.reduce(0) { $0 + $1.effectiveML })
```

- [ ] **Step 4 : Type-check iOS**

Run la commande de type-check complète.
Expected: 0 erreur. (`DrinkType` / `clampedDayTotal` viennent de `WelloKit`, déjà importé ligne 3.)

- [ ] **Step 5 : Commit**

```bash
git add Wello/Wello/Services/HydrationStore.swift
git commit -m "feat(premium): log typé + consommé = hydratation effective bornée"
```

---

## Task 6 : Feuille de saisie typée (MainView)

**Files:**
- Modify: `Wello/Wello/Views/MainView.swift`

- [ ] **Step 1 : Jauge sur l'hydratation effective**

Modify `Wello/Wello/Views/MainView.swift`.

Remplacer la propriété `consommé` (ligne 22) :

```swift
    private var consommé: Int { logsDuJour.reduce(0) { $0 + $1.amountML } }
```

par :

```swift
    private var consommé: Int { clampedDayTotal(logsDuJour.reduce(0) { $0 + $1.effectiveML }) }
```

(`clampedDayTotal` vient de `WelloKit`, déjà importé ligne 3.)

- [ ] **Step 2 : Brancher la feuille sur la saisie typée**

Remplacer le modifier `.sheet(isPresented: $afficheSaisie)` (lignes 102–104) :

```swift
            .sheet(isPresented: $afficheSaisie) {
                SaisieEauSheet { ml in Task { await store.log(ml: ml) } }
            }
```

par :

```swift
            .sheet(isPresented: $afficheSaisie) {
                SaisieEauSheet { ml, drink, coeff in
                    Task { await store.log(ml: ml, drink: drink, coefficient: coeff) }
                }
            }
```

- [ ] **Step 3 : Réécrire `SaisieEauSheet` (typée + gating)**

Remplacer entièrement la struct privée `SaisieEauSheet` (lignes 140–174) par :

```swift
/// Feuille de saisie d'une prise : eau seule en gratuit (+ teasing), choix de la boisson en Wello+.
private struct SaisieEauSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(DrinkCatalog.self) private var drinks
    @State private var ml = 300
    @State private var drink: DrinkType = .water
    @State private var paywall = false
    /// (volume, boisson, coefficient snapshoté).
    let onConfirm: (Int, DrinkType, Double) -> Void

    private var premium: Bool { entitlements.isUnlocked(.customDrinks) }
    private var coefficient: Double { drinks.coefficient(for: drink) }
    private var effectif: Int { effectiveHydrationML(volumeML: ml, coefficient: coefficient) }

    var body: some View {
        NavigationStack {
            Form {
                if premium {
                    Section {
                        Picker(selection: $drink) {
                            ForEach(DrinkType.allCases, id: \.self) { d in
                                Label(d.label, systemImage: d.icon).tag(d)
                            }
                        } label: {
                            Text("Boisson").font(.system(.body, design: .rounded))
                        }
                    }
                }
                Section {
                    Stepper(value: $ml, in: 10...3000, step: 10) {
                        HStack {
                            Text("Quantité").font(.system(.body, design: .rounded))
                            Spacer()
                            Text("\(ml) ml")
                                .font(.system(.body, design: .rounded).weight(.medium))
                                .foregroundStyle(WelloTheme.inkSoft)
                        }
                    }
                } footer: {
                    if premium && coefficient != 1.0 {
                        Text("≈ \(effectif) ml hydratants (coefficient \(coefficient, format: .number.precision(.fractionLength(0...2))))")
                            .font(.system(.caption, design: .rounded))
                    }
                }
                if !premium {
                    Section {
                        PremiumGateCard(bénéfice: "Café, thé, alcool… au-delà de l'eau") {
                            paywall = true
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .welloBackground()
            .navigationTitle(premium ? "Ajouter une boisson" : "Ajouter de l'eau")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") {
                        onConfirm(ml, premium ? drink : .water, premium ? coefficient : 1.0)
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $paywall) {
                PaywallView(bénéfice: "Bois ce que tu veux, compté juste")
            }
        }
        .presentationDetents([.height(premium ? 320 : 240)])
    }
}
```

- [ ] **Step 4 : Mettre à jour la preview de MainView**

Remplacer le bloc `#Preview` en bas de `MainView.swift` (lignes 176–183) :

```swift
#if DEBUG
#Preview {
    let container = PreviewSupport.container()
    return MainView()
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
    return MainView()
        .modelContainer(container)
        .environment(PreviewSupport.store(container))
        .environment(PreviewSupport.entitlements(.plus))
        .environment(PreviewSupport.drinkCatalog())
}
#endif
```

- [ ] **Step 5 : Type-check iOS**

Run la commande de type-check complète.
Expected: 0 erreur.

- [ ] **Step 6 : Commit**

```bash
git add Wello/Wello/Views/MainView.swift
git commit -m "feat(premium): jauge effective + feuille de saisie typée avec gating"
```

---

## Task 7 : Détail du jour — boisson + effectif

**Files:**
- Modify: `Wello/Wello/Views/DayDetailView.swift`

- [ ] **Step 1 : Importer WelloKit + total effectif**

Modify `Wello/Wello/Views/DayDetailView.swift`.

Remplacer les deux premières lignes d'import (lignes 1–2) :

```swift
import SwiftUI
import SwiftData
```

par :

```swift
import SwiftUI
import SwiftData
import WelloKit
```

Remplacer la propriété `total` (ligne 13) :

```swift
    private var total: Int { prises.reduce(0) { $0 + $1.amountML } }
```

par :

```swift
    private var total: Int { clampedDayTotal(prises.reduce(0) { $0 + $1.effectiveML }) }
```

- [ ] **Step 2 : Ligne avec icône/nom de boisson + effectif**

Remplacer la méthode `ligne(_:)` (lignes 44–61) :

```swift
    private func ligne(_ prise: HydrationLog) -> some View {
        HStack(spacing: 12) {
            Image(systemName: prise.source == "healthkit" ? "heart.fill" : "drop.fill")
                .foregroundStyle(prise.source == "healthkit" ? .pink : WelloTheme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(prise.amountML) ml")
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .foregroundStyle(WelloTheme.ink)
                Text(prise.source == "healthkit" ? "depuis Santé" : "saisie dans Wello")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(WelloTheme.inkSoft)
            }
            Spacer()
            Text(prise.loggedAt, format: .dateTime.hour().minute())
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(WelloTheme.inkSoft)
        }
    }
```

par :

```swift
    private func ligne(_ prise: HydrationLog) -> some View {
        let typé = prise.coefficient != 1.0
        return HStack(spacing: 12) {
            Image(systemName: prise.source == "healthkit" ? "heart.fill" : prise.drink.icon)
                .foregroundStyle(prise.source == "healthkit" ? .pink : WelloTheme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(typé ? "\(prise.amountML) ml de \(prise.drink.label.lowercased())"
                          : "\(prise.amountML) ml")
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .foregroundStyle(WelloTheme.ink)
                Text(sousTitre(prise, typé: typé))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(WelloTheme.inkSoft)
            }
            Spacer()
            Text(prise.loggedAt, format: .dateTime.hour().minute())
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(WelloTheme.inkSoft)
        }
    }

    /// Sous-titre : provenance pour l'eau/HealthKit, hydratation effective pour une boisson typée.
    private func sousTitre(_ prise: HydrationLog, typé: Bool) -> String {
        if prise.source == "healthkit" { return "depuis Santé" }
        if typé { return "≈ \(prise.effectiveML) ml hydratants" }
        return "saisie dans Wello"
    }
```

- [ ] **Step 3 : Type-check iOS**

Run la commande de type-check complète.
Expected: 0 erreur.

- [ ] **Step 4 : Commit**

```bash
git add Wello/Wello/Views/DayDetailView.swift
git commit -m "feat(premium): détail du jour avec boisson + hydratation effective"
```

---

## Task 8 : Historique — consommation effective

**Files:**
- Modify: `Wello/Wello/Views/HistoryView.swift`

- [ ] **Step 1 : Consommation par jour = effectif borné**

Modify `Wello/Wello/Views/HistoryView.swift`.

Remplacer la méthode `consommationParJour()` (lignes 110–118) :

```swift
    /// Consommé (ml) par jour, agrégé en un seul passage sur les logs.
    private func consommationParJour() -> [Date: Int] {
        let cal = Calendar.current
        var map: [Date: Int] = [:]
        for log in logs {
            map[cal.startOfDay(for: log.loggedAt), default: 0] += log.amountML
        }
        return map
    }
```

par :

```swift
    /// Consommé effectif (ml) par jour, agrégé en un seul passage sur les logs.
    /// Chaque jour est borné à ≥ 0 (une journée « alcool » ne devient pas négative).
    private func consommationParJour() -> [Date: Int] {
        let cal = Calendar.current
        var map: [Date: Int] = [:]
        for log in logs {
            map[cal.startOfDay(for: log.loggedAt), default: 0] += log.effectiveML
        }
        return map.mapValues(clampedDayTotal)
    }
```

- [ ] **Step 2 : Type-check iOS**

Run la commande de type-check complète.
Expected: 0 erreur. (`clampedDayTotal` vient de `WelloKit`, déjà importé ligne 4.)

- [ ] **Step 3 : Commit**

```bash
git add Wello/Wello/Views/HistoryView.swift
git commit -m "feat(premium): historique sur hydratation effective"
```

---

## Task 9 : Analyses — consommation effective

**Files:**
- Modify: `Wello/Wello/Views/AnalyticsView.swift`

- [ ] **Step 1 : Consommation par jour = effectif borné**

Modify `Wello/Wello/Views/AnalyticsView.swift`.

Remplacer la méthode `consommationParJour()` (lignes 39–47) :

```swift
    /// Consommé (ml) par jour, agrégé en un seul passage sur les logs.
    private func consommationParJour() -> [Date: Int] {
        let cal = Calendar.current
        var map: [Date: Int] = [:]
        for log in logs {
            map[cal.startOfDay(for: log.loggedAt), default: 0] += log.amountML
        }
        return map
    }
```

par :

```swift
    /// Consommé effectif (ml) par jour, agrégé en un seul passage sur les logs (jours bornés à ≥ 0).
    private func consommationParJour() -> [Date: Int] {
        let cal = Calendar.current
        var map: [Date: Int] = [:]
        for log in logs {
            map[cal.startOfDay(for: log.loggedAt), default: 0] += log.effectiveML
        }
        return map.mapValues(clampedDayTotal)
    }
```

- [ ] **Step 2 : Répartition horaire sur l'effectif**

Remplacer la méthode `entréesHoraires()` (lignes 58–65) :

```swift
    /// (heure, ml) des prises sur les 30 derniers jours, pour la répartition.
    private func entréesHoraires() -> [(hour: Int, ml: Int)] {
        let cal = Calendar.current
        let borne = cal.date(byAdding: .day, value: -29, to: cal.startOfDay(for: .now))!
        return logs
            .filter { $0.loggedAt >= borne }
            .map { (hour: cal.component(.hour, from: $0.loggedAt), ml: $0.amountML) }
    }
```

par :

```swift
    /// (heure, hydratation effective) des prises sur les 30 derniers jours, pour la répartition.
    private func entréesHoraires() -> [(hour: Int, ml: Int)] {
        let cal = Calendar.current
        let borne = cal.date(byAdding: .day, value: -29, to: cal.startOfDay(for: .now))!
        return logs
            .filter { $0.loggedAt >= borne }
            .map { (hour: cal.component(.hour, from: $0.loggedAt), ml: max(0, $0.effectiveML)) }
    }
```

- [ ] **Step 3 : Type-check iOS**

Run la commande de type-check complète.
Expected: 0 erreur. (`clampedDayTotal` vient de `WelloKit`, déjà importé ligne 4.)

- [ ] **Step 4 : Commit**

```bash
git add Wello/Wello/Views/AnalyticsView.swift
git commit -m "feat(premium): analyses sur hydratation effective"
```

---

## Task 10 : Profil — section « Boissons » (édition gated)

**Files:**
- Modify: `Wello/Wello/Views/ProfileView.swift`

- [ ] **Step 1 : Injecter DrinkCatalog**

Modify `Wello/Wello/Views/ProfileView.swift`.

Après la ligne `@Environment(EntitlementStore.self) private var entitlements` (ligne 10), ajouter :

```swift
    @Environment(DrinkCatalog.self) private var drinks
```

- [ ] **Step 2 : Ajouter la section Boissons**

Dans `body`, juste **après** la fermeture de la `Section` du bouton « Wello+ » (la `}` de la ligne 49) et **avant** `if let profil {` (ligne 50), insérer :

```swift
                Section {
                    if entitlements.isUnlocked(.customDrinks) {
                        ForEach(DrinkType.allCases.filter { $0 != .water }, id: \.self) { drink in
                            Stepper(value: Binding(get: { drinks.coefficient(for: drink) },
                                                   set: { drinks.setCoefficient($0, for: drink) }),
                                    in: coefficientRange, step: 0.05) {
                                HStack(spacing: 12) {
                                    Image(systemName: drink.icon)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(WelloTheme.accent)
                                        .frame(width: 30, height: 30)
                                        .background(WelloTheme.accent.opacity(0.15), in: Circle())
                                    Text(drink.label).font(.system(.body, design: .rounded))
                                    Spacer()
                                    Text(drinks.coefficient(for: drink),
                                         format: .number.precision(.fractionLength(0...2)))
                                        .font(.system(.body, design: .rounded).weight(.medium))
                                        .foregroundStyle(drinks.isCustomized(drink) ? WelloTheme.accentDeep : WelloTheme.inkSoft)
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                if drinks.isCustomized(drink) {
                                    Button("Réinitialiser") { drinks.reset(drink) }
                                }
                            }
                        }
                    } else {
                        Button {
                            paywall = true
                        } label: {
                            HStack {
                                label("Boissons personnalisées", nil,
                                      icon: "cup.and.saucer.fill", teinte: WelloTheme.accent)
                                Spacer()
                                Text("Débloquer")
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
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Boissons personnalisées, débloquer")
                        .accessibilityHint("Ouvre l'offre Wello+")
                    }
                } header: {
                    Text("Boissons")
                } footer: {
                    Text("Coefficient d'hydratation par boisson (eau = 1,0). Ajuste selon ton ressenti ; valeurs indicatives, non médicales.")
                        .font(.system(.caption, design: .rounded))
                }
```

- [ ] **Step 3 : Mettre à jour les previews**

Remplacer le bloc `#Preview` en bas de `ProfileView.swift` (lignes 189–197) :

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

par :

```swift
#if DEBUG
#Preview("Gratuit") {
    let container = PreviewSupport.container()
    return ProfileView()
        .modelContainer(container)
        .environment(PreviewSupport.store(container))
        .environment(PreviewSupport.entitlements(.free))
        .environment(PreviewSupport.drinkCatalog())
}

#Preview("Wello+") {
    let container = PreviewSupport.container()
    return ProfileView()
        .modelContainer(container)
        .environment(PreviewSupport.store(container))
        .environment(PreviewSupport.entitlements(.plus))
        .environment(PreviewSupport.drinkCatalog())
}
#endif
```

- [ ] **Step 4 : Type-check iOS**

Run la commande de type-check complète.
Expected: 0 erreur. (`DrinkType` / `coefficientRange` viennent de `WelloKit`, déjà importé ligne 3.)

- [ ] **Step 5 : Commit**

```bash
git add Wello/Wello/Views/ProfileView.swift
git commit -m "feat(premium): section Boissons au Profil (édition des coefficients, gated)"
```

---

## Vérification finale

- [ ] **Logique pure :** `cd WelloKit && swift test` → tout passe (dont la suite `Drink`).
- [ ] **App iOS :** la commande de type-check complète → 0 erreur.
- [ ] **Previews (Xcode, manuel) :** feuille de saisie en `.plus` (sélecteur de boisson + effectif live) vs `.free` (eau-seule + teasing) ; section « Boissons » du Profil éditable en `.plus`, gate en `.free` ; `DayDetailView` montre la prise « café · ≈ 200 ml » ; jauge/historique inchangés en eau pure.
- [ ] **Migration (Xcode, manuel) :** build sur une base existante → ouverture sans perte, anciennes prises en `water`/1.0, jauge identique.

## Étapes Xcode manuelles (hors CLI)

- Vérifier la migration légère SwiftData sur un device/simulateur portant déjà des données.
- Aucune nouvelle capability ni clé Info.plist (réutilise HealthKit existant ; écrit toujours de l'« Eau »).
