# App watchOS (Phase 2) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Une app Apple Watch autonome (jauge + ajout rapide d'eau, hors-ligne géré) qui réutilise `WelloKit`, se synchronise avec l'iPhone via WatchConnectivity (intakes Watch→iPhone) et un mirroir d'état (iPhone→Watch), sans CloudKit ni store partagé. Périmètre : **app Watch seule** (complication de cadran plus tard).

**Architecture:** Le cœur testable vit dans `WelloKit` : `PriseWatch` + `WatchSyncSnapshot` (codecs dictionnaire plist-safe pour `WCSession`) et `ÉtatHydratationWatch` (réducteur pur : `consommé = snapshot.consomméML + Σ prises locales non acquittées` ; objectif = `max(poussé, recalculé)`). L'iPhone reste l'**unique écrivain HealthKit** et l'autorité du consommé ; il pousse un `WatchSyncSnapshot` après chaque mutation et ingère les `PriseWatch` reçues (dédup par `HydrationLog.watchUUID`). La Watch logue de façon optimiste, met les prises en file (`transferUserInfo`), et redessine la jauge via `WidgetProgress`.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, WatchConnectivity, HealthKit (lecture watchOS), Swift Testing (`swift test`). Patterns existants : logique pure WelloKit, pattern MV, services derrière protocoles + mocks.

**Spec :** `docs/superpowers/specs/2026-06-19-wello-watchos-design.md`.

> **Branche :** déjà sur `feat/watchos` (le spec + ce plan y sont commités). Trailer de commit :
> `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.

**Note de vérification :** tâches WelloKit → `cd WelloKit && swift test`. Tâches app iPhone → type-check iOS hors Xcode (voir `CLAUDE.md`) ; `WatchConnectivity` est dans le SDK iOS, donc inclus. Le code de la **cible Watch** (watchOS-only + `@main` + capability) n'est pas pilotable en CLI : il est fourni complet et validé en **preview/simulateur Xcode** par l'utilisateur (Task 6/7).

---

## File Structure

**Créés :**
- `WelloKit/Sources/WelloKit/Models/WatchSync.swift` — `PriseWatch` + `WatchSyncSnapshot` (codecs dictionnaire).
- `WelloKit/Sources/WelloKit/WatchHydrationState.swift` — `ÉtatHydratationWatch` (réducteur pur).
- `WelloKit/Tests/WelloKitTests/WatchSyncTests.swift` — codecs + round-trip.
- `WelloKit/Tests/WelloKitTests/WatchHydrationStateTests.swift` — réconciliation + recalcul.
- `Wello/Wello/Services/WatchConnectivityService.swift` — `WatchSyncing` réel (`WCSessionDelegate`).
- `Wello/WelloWatch/WelloWatchApp.swift` — `@main` de l'app Watch.
- `Wello/WelloWatch/WatchStore.swift` — `@Observable` Watch (état + persistance file locale).
- `Wello/WelloWatch/WatchConnectivityClient.swift` — `WCSessionDelegate` côté Watch.
- `Wello/WelloWatch/HealthKitWatchService.swift` — lecture énergie active (watchOS).
- `Wello/WelloWatch/WatchMainView.swift` — jauge + boutons + annuler.

**Modifiés :**
- `Wello/Wello/Models/HydrationLog.swift` — champ `watchUUID: UUID?`.
- `Wello/Wello/Services/ServiceProtocols.swift` — protocole `WatchSyncing`.
- `Wello/Wello/Services/Mocks.swift` — mock `WatchSyncing`.
- `Wello/Wello/Services/HydrationStore.swift` — `watchSync`, `snapshotWatch()`, `enregistrerPriseDistante`, hooks.
- `Wello/Wello/App/WelloApp.swift` — création/injection du service Watch + `onPriseDistante`.
- `README.md`, `CLAUDE.md` — docs Phase 2 (app Watch).

---

## Task 1 : WelloKit — `PriseWatch` + `WatchSyncSnapshot` (TDD)

**Files:**
- Create: `WelloKit/Sources/WelloKit/Models/WatchSync.swift`
- Test: `WelloKit/Tests/WelloKitTests/WatchSyncTests.swift`

- [ ] **Step 1 : Écrire les tests (rouge)**

Create `WelloKit/Tests/WelloKitTests/WatchSyncTests.swift` :

```swift
import Testing
import Foundation
@testable import WelloKit

@Suite("WatchSync — codecs dictionnaire")
struct WatchSyncTests {

    @Test("PriseWatch : round-trip dictionnaire plist-safe")
    func priseRoundTrip() {
        let p = PriseWatch(id: UUID(), amountML: 250, loggedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let dict = p.dictionnaire()
        // Types plist-safe attendus (transportables par WCSession).
        #expect(dict["id"] is String)
        #expect(dict["amountML"] is Int)
        #expect(dict["loggedAt"] is Double)
        let décodé = PriseWatch(dictionnaire: dict)
        #expect(décodé == p)
    }

    @Test("PriseWatch : dictionnaire invalide → nil")
    func priseInvalide() {
        #expect(PriseWatch(dictionnaire: [:]) == nil)
        #expect(PriseWatch(dictionnaire: ["id": "pas-un-uuid", "amountML": 1, "loggedAt": 0.0]) == nil)
    }

    @Test("WatchSyncSnapshot : round-trip complet")
    func snapshotRoundTrip() {
        let s = WatchSyncSnapshot(
            objectifML: 2300, consomméML: 1200, quickAdds: [150, 250, 500], configuré: true,
            sexeRaw: "homme", etatPhysioRaw: nil, renalBonusML: 0,
            activitySensitivity: 1.0, weatherSensitivity: 1.0, manualAdjustmentML: 0,
            acquittés: [UUID(), UUID()], générémLe: Date(timeIntervalSince1970: 1_700_000_000))
        let décodé = WatchSyncSnapshot(dictionnaire: s.dictionnaire())
        #expect(décodé == s)
    }

    @Test("WatchSyncSnapshot : champs optionnels nil préservés")
    func snapshotOptionnels() {
        let s = WatchSyncSnapshot(
            objectifML: 0, consomméML: 0, quickAdds: [150, 250, 500], configuré: false,
            sexeRaw: nil, etatPhysioRaw: nil, renalBonusML: 0,
            activitySensitivity: 1.0, weatherSensitivity: 1.0, manualAdjustmentML: 0,
            acquittés: [], générémLe: Date(timeIntervalSince1970: 0))
        let décodé = WatchSyncSnapshot(dictionnaire: s.dictionnaire())
        #expect(décodé == s)
        #expect(décodé?.sexeRaw == nil)
        #expect(décodé?.acquittés.isEmpty == true)
    }

    @Test("WatchSyncSnapshot : dictionnaire incomplet → nil")
    func snapshotInvalide() {
        #expect(WatchSyncSnapshot(dictionnaire: ["objectifML": 2000]) == nil)
    }
}
```

- [ ] **Step 2 : Lancer les tests (échec attendu)**

Run: `cd WelloKit && swift test --filter WatchSync`
Expected: FAIL — `cannot find 'PriseWatch' / 'WatchSyncSnapshot' in scope`.

- [ ] **Step 3 : Créer `WatchSync.swift`**

Create `WelloKit/Sources/WelloKit/Models/WatchSync.swift` :

```swift
import Foundation

/// Une prise d'eau saisie au poignet, en attente de synchronisation vers l'iPhone.
/// Transportée par `WCSession.transferUserInfo` (file à livraison garantie) via son codec
/// dictionnaire plist-safe. Pure et testable en CLI.
public struct PriseWatch: Sendable, Equatable, Codable, Identifiable {
    public let id: UUID
    public let amountML: Int
    public let loggedAt: Date

    public init(id: UUID = UUID(), amountML: Int, loggedAt: Date = .init()) {
        self.id = id
        self.amountML = amountML
        self.loggedAt = loggedAt
    }

    /// Dictionnaire plist-safe pour `WCSession` (UUID→String, Date→Double).
    public func dictionnaire() -> [String: Any] {
        ["id": id.uuidString, "amountML": amountML, "loggedAt": loggedAt.timeIntervalSince1970]
    }

    public init?(dictionnaire dict: [String: Any]) {
        guard let ids = dict["id"] as? String, let id = UUID(uuidString: ids),
              let ml = dict["amountML"] as? Int,
              let ts = dict["loggedAt"] as? Double else { return nil }
        self.init(id: id, amountML: ml, loggedAt: Date(timeIntervalSince1970: ts))
    }
}

/// Mirroir d'état poussé par l'iPhone vers la Watch (`updateApplicationContext`, coalescé,
/// dernier-état-gagne). Porte l'objectif/consommé autoritaires, les montants rapides, un profil
/// minimal (pour le recalcul autonome) et l'ensemble des `id` de prises Watch déjà acquittées
/// par l'iPhone (pour purger l'affichage optimiste). Pur et testable en CLI.
public struct WatchSyncSnapshot: Sendable, Equatable, Codable {
    public let objectifML: Int
    public let consomméML: Int
    public let quickAdds: [Int]
    public let configuré: Bool
    public let sexeRaw: String?
    public let etatPhysioRaw: String?
    public let renalBonusML: Int
    public let activitySensitivity: Double
    public let weatherSensitivity: Double
    public let manualAdjustmentML: Int
    public let acquittés: [UUID]
    public let générémLe: Date

    public init(objectifML: Int, consomméML: Int, quickAdds: [Int], configuré: Bool,
                sexeRaw: String?, etatPhysioRaw: String?, renalBonusML: Int,
                activitySensitivity: Double, weatherSensitivity: Double, manualAdjustmentML: Int,
                acquittés: [UUID], générémLe: Date) {
        self.objectifML = objectifML
        self.consomméML = consomméML
        self.quickAdds = quickAdds
        self.configuré = configuré
        self.sexeRaw = sexeRaw
        self.etatPhysioRaw = etatPhysioRaw
        self.renalBonusML = renalBonusML
        self.activitySensitivity = activitySensitivity
        self.weatherSensitivity = weatherSensitivity
        self.manualAdjustmentML = manualAdjustmentML
        self.acquittés = acquittés
        self.générémLe = générémLe
    }

    /// Dictionnaire plist-safe pour `WCSession`. Les optionnels absents sont simplement omis.
    public func dictionnaire() -> [String: Any] {
        var d: [String: Any] = [
            "objectifML": objectifML,
            "consomméML": consomméML,
            "quickAdds": quickAdds,
            "configuré": configuré,
            "renalBonusML": renalBonusML,
            "activitySensitivity": activitySensitivity,
            "weatherSensitivity": weatherSensitivity,
            "manualAdjustmentML": manualAdjustmentML,
            "acquittés": acquittés.map(\.uuidString),
            "générémLe": générémLe.timeIntervalSince1970
        ]
        if let sexeRaw { d["sexeRaw"] = sexeRaw }
        if let etatPhysioRaw { d["etatPhysioRaw"] = etatPhysioRaw }
        return d
    }

    public init?(dictionnaire d: [String: Any]) {
        guard let objectifML = d["objectifML"] as? Int,
              let consomméML = d["consomméML"] as? Int,
              let quickAdds = d["quickAdds"] as? [Int],
              let configuré = d["configuré"] as? Bool,
              let renalBonusML = d["renalBonusML"] as? Int,
              let activitySensitivity = d["activitySensitivity"] as? Double,
              let weatherSensitivity = d["weatherSensitivity"] as? Double,
              let manualAdjustmentML = d["manualAdjustmentML"] as? Int,
              let acquittésRaw = d["acquittés"] as? [String],
              let ts = d["générémLe"] as? Double else { return nil }
        self.init(
            objectifML: objectifML, consomméML: consomméML, quickAdds: quickAdds, configuré: configuré,
            sexeRaw: d["sexeRaw"] as? String, etatPhysioRaw: d["etatPhysioRaw"] as? String,
            renalBonusML: renalBonusML, activitySensitivity: activitySensitivity,
            weatherSensitivity: weatherSensitivity, manualAdjustmentML: manualAdjustmentML,
            acquittés: acquittésRaw.compactMap(UUID.init(uuidString:)),
            générémLe: Date(timeIntervalSince1970: ts))
    }
}
```

- [ ] **Step 4 : Tests verts**

Run: `cd WelloKit && swift test --filter WatchSync`
Expected: PASS (5 tests).

- [ ] **Step 5 : Commit**

```bash
git add WelloKit/Sources/WelloKit/Models/WatchSync.swift \
  WelloKit/Tests/WelloKitTests/WatchSyncTests.swift
git commit -m "feat(kit): PriseWatch + WatchSyncSnapshot — codecs WCSession (purs, testés)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2 : WelloKit — `ÉtatHydratationWatch` (TDD)

Réducteur pur de l'affichage Watch : consommé = autoritaire + prises non acquittées ; objectif =
max(poussé, recalculé). Réutilise `WidgetProgress` et `HydrationCalculator`.

**Files:**
- Create: `WelloKit/Sources/WelloKit/WatchHydrationState.swift`
- Test: `WelloKit/Tests/WelloKitTests/WatchHydrationStateTests.swift`

- [ ] **Step 1 : Écrire les tests (rouge)**

Create `WelloKit/Tests/WelloKitTests/WatchHydrationStateTests.swift` :

```swift
import Testing
import Foundation
@testable import WelloKit

@Suite("ÉtatHydratationWatch")
struct WatchHydrationStateTests {

    private func snapshot(objectif: Int = 2300, consommé: Int = 1000, acquittés: [UUID] = [],
                          sexe: String? = "homme") -> WatchSyncSnapshot {
        WatchSyncSnapshot(
            objectifML: objectif, consomméML: consommé, quickAdds: [150, 250, 500], configuré: sexe != nil,
            sexeRaw: sexe, etatPhysioRaw: nil, renalBonusML: 0,
            activitySensitivity: 1.0, weatherSensitivity: 1.0, manualAdjustmentML: 0,
            acquittés: acquittés, générémLe: .init(timeIntervalSince1970: 1_700_000_000))
    }

    @Test("Sans snapshot : non configuré, consommé 0, objectif 0")
    func vide() {
        let é = ÉtatHydratationWatch()
        #expect(é.configuré == false)
        #expect(é.consomméML == 0)
        #expect(é.objectifML == 0)
    }

    @Test("Consommé = autoritaire + prises non acquittées")
    func consomméOptimiste() {
        var é = ÉtatHydratationWatch()
        é.appliquer(snapshot(consommé: 1000))
        é.ajouterPrise(PriseWatch(amountML: 250))
        é.ajouterPrise(PriseWatch(amountML: 150))
        #expect(é.consomméML == 1400)   // 1000 + 250 + 150
    }

    @Test("Application d'un snapshot : purge les prises acquittées")
    func purgeAcquittées() {
        var é = ÉtatHydratationWatch()
        let p = PriseWatch(amountML: 250)
        é.appliquer(snapshot(consommé: 1000))
        é.ajouterPrise(p)
        #expect(é.consomméML == 1250)
        // L'iPhone a absorbé p (consommé autoritaire monte à 1250, p acquittée) → plus de double compte.
        é.appliquer(snapshot(consommé: 1250, acquittés: [p.id]))
        #expect(é.consomméML == 1250)
        #expect(é.prisesEnAttente.isEmpty)
    }

    @Test("Hors-ligne : les prises s'empilent sur le dernier consommé connu")
    func horsLigne() {
        var é = ÉtatHydratationWatch()
        é.appliquer(snapshot(consommé: 800))
        é.ajouterPrise(PriseWatch(amountML: 250))
        é.ajouterPrise(PriseWatch(amountML: 250))
        #expect(é.consomméML == 1300)   // aucun acquittement reçu
    }

    @Test("Objectif = max(poussé, recalculé depuis énergie active)")
    func recalculObjectif() {
        var é = ÉtatHydratationWatch()
        é.appliquer(snapshot(objectif: 2000, sexe: "homme"))   // base homme 2000, sans activité
        é.mettreÀJourÉnergie(600)                              // +600 ml d'activité (1 ml/kcal)
        #expect(é.objectifML == 2600)                          // max(2000, 2000+600)
    }

    @Test("Objectif : le poussé gagne s'il est supérieur (météo connue de l'iPhone)")
    func pousséGagne() {
        var é = ÉtatHydratationWatch()
        é.appliquer(snapshot(objectif: 2900, sexe: "homme"))   // inclut un bonus météo
        é.mettreÀJourÉnergie(100)                              // recalcul local 2100 < 2900
        #expect(é.objectifML == 2900)
    }

    @Test("Sexe inconnu : pas de recalcul, on garde le poussé")
    func sexeInconnu() {
        var é = ÉtatHydratationWatch()
        é.appliquer(snapshot(objectif: 1800, sexe: nil))
        é.mettreÀJourÉnergie(500)
        #expect(é.objectifML == 1800)
    }

    @Test("Annuler la dernière prise en attente")
    func annuler() {
        var é = ÉtatHydratationWatch()
        é.appliquer(snapshot(consommé: 1000))
        é.ajouterPrise(PriseWatch(amountML: 250))
        let p2 = PriseWatch(amountML: 150)
        é.ajouterPrise(p2)
        let retirée = é.annulerDernièreEnAttente()
        #expect(retirée == p2)
        #expect(é.consomméML == 1250)
    }

    @Test("progress reflète consommé/objectif via WidgetProgress")
    func progress() {
        var é = ÉtatHydratationWatch()
        é.appliquer(snapshot(objectif: 2000, consommé: 1000))
        #expect(é.progress.fraction == 0.5)
        #expect(é.progress.pourcent == 50)
    }
}
```

- [ ] **Step 2 : Lancer les tests (échec attendu)**

Run: `cd WelloKit && swift test --filter ÉtatHydratationWatch`
Expected: FAIL — `cannot find 'ÉtatHydratationWatch' in scope`.

- [ ] **Step 3 : Créer `WatchHydrationState.swift`**

Create `WelloKit/Sources/WelloKit/WatchHydrationState.swift` :

```swift
import Foundation

/// État d'affichage de l'app Watch, dérivé **purement** d'un snapshot autoritaire (iPhone) et
/// d'une file de prises locales optimistes. Cœur de la réconciliation sans double comptage :
/// `consommé = snapshot.consomméML + Σ prises locales non acquittées`. Pur et testable en CLI.
public struct ÉtatHydratationWatch: Sendable, Equatable {
    /// Dernier mirroir reçu de l'iPhone. `nil` tant que la Watch n'a jamais synchronisé.
    public private(set) var snapshot: WatchSyncSnapshot?
    /// Prises saisies au poignet, persistées jusqu'à acquittement par l'iPhone.
    public private(set) var prisesLocales: [PriseWatch]
    /// Dernière énergie active lue sur la Watch (kcal), pour le recalcul autonome de l'objectif.
    public private(set) var énergieActiveKcal: Double

    public init(snapshot: WatchSyncSnapshot? = nil,
                prisesLocales: [PriseWatch] = [],
                énergieActiveKcal: Double = 0) {
        self.snapshot = snapshot
        self.prisesLocales = prisesLocales
        self.énergieActiveKcal = énergieActiveKcal
    }

    /// Vrai dès que l'iPhone a fourni un objectif configuré.
    public var configuré: Bool { snapshot?.configuré ?? false }

    /// Montants des 3 boutons d'ajout rapide (repli sur les défauts).
    public var quickAdds: [Int] { snapshot?.quickAdds ?? [150, 250, 500] }

    /// Prises pas encore absorbées par l'iPhone (id ∉ acquittés du snapshot).
    public var prisesEnAttente: [PriseWatch] {
        let acquittés = Set(snapshot?.acquittés ?? [])
        return prisesLocales.filter { !acquittés.contains($0.id) }
    }

    /// Consommé affiché : total autoritaire + prises optimistes non acquittées.
    public var consomméML: Int {
        (snapshot?.consomméML ?? 0) + prisesEnAttente.reduce(0) { $0 + $1.amountML }
    }

    /// Objectif affiché : `max(poussé, recalculé)`. La météo reste portée par le poussé (iPhone) ;
    /// la part « activité » peut monter au poignet via l'énergie active locale. 0 si non configuré.
    public var objectifML: Int {
        guard let s = snapshot, s.configuré else { return 0 }
        return max(s.objectifML, objectifRecalculé(s) ?? 0)
    }

    /// Affichage de progression (anneau/%/libellés), réutilise le type widget.
    public var progress: WidgetProgress {
        WidgetProgress(consomméML: consomméML, objectifML: objectifML)
    }

    // MARK: Mutations

    /// Ajoute une prise locale (affichage optimiste immédiat).
    public mutating func ajouterPrise(_ prise: PriseWatch) {
        prisesLocales.append(prise)
    }

    /// Applique un snapshot reçu de l'iPhone et purge les prises locales désormais acquittées.
    public mutating func appliquer(_ s: WatchSyncSnapshot) {
        snapshot = s
        let acquittés = Set(s.acquittés)
        prisesLocales.removeAll { acquittés.contains($0.id) }
    }

    /// Met à jour l'énergie active (kcal) lue sur la Watch.
    public mutating func mettreÀJourÉnergie(_ kcal: Double) {
        énergieActiveKcal = kcal
    }

    /// Retire et renvoie la dernière prise **en attente** (non acquittée). `nil` s'il n'y en a pas.
    @discardableResult
    public mutating func annulerDernièreEnAttente() -> PriseWatch? {
        let acquittés = Set(snapshot?.acquittés ?? [])
        guard let idx = prisesLocales.lastIndex(where: { !acquittés.contains($0.id) }) else { return nil }
        return prisesLocales.remove(at: idx)
    }

    // MARK: Recalcul

    /// Objectif recalculé au poignet depuis le profil du snapshot + l'énergie active locale.
    /// `nil` si le sexe est inconnu (on ne fabrique pas de base sans lui).
    private func objectifRecalculé(_ s: WatchSyncSnapshot) -> Int? {
        guard let sexeRaw = s.sexeRaw, let sexe = BiologicalSex(rawValue: sexeRaw) else { return nil }
        let inputs = CalculatorInputs(
            sex: sexe,
            activeEnergyKcal: énergieActiveKcal,
            weather: nil,   // la météo reste portée par l'objectif poussé
            physiologicalState: s.etatPhysioRaw.flatMap(PhysiologicalState.init(rawValue:)) ?? .aucun,
            renalBonusML: s.renalBonusML,
            tuning: CalculatorTuning(activityMultiplier: s.activitySensitivity,
                                     weatherMultiplier: s.weatherSensitivity,
                                     manualAdjustmentML: s.manualAdjustmentML))
        return HydrationCalculator().calculate(inputs).totalML
    }
}
```

- [ ] **Step 4 : Tests verts**

Run: `cd WelloKit && swift test --filter ÉtatHydratationWatch`
Expected: PASS (9 tests).

- [ ] **Step 5 : Suite complète (non-régression)**

Run: `cd WelloKit && swift test`
Expected: PASS (toute la suite verte).

- [ ] **Step 6 : Commit**

```bash
git add WelloKit/Sources/WelloKit/WatchHydrationState.swift \
  WelloKit/Tests/WelloKitTests/WatchHydrationStateTests.swift
git commit -m "feat(kit): ÉtatHydratationWatch — réconciliation consommé/objectif (pur, testé)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3 : Modèle `HydrationLog.watchUUID` + protocole `WatchSyncing` + mock (app)

**Files:**
- Modify: `Wello/Wello/Models/HydrationLog.swift`
- Modify: `Wello/Wello/Services/ServiceProtocols.swift`
- Modify: `Wello/Wello/Services/Mocks.swift`

- [ ] **Step 1 : Champ `watchUUID` sur `HydrationLog`**

Dans `Wello/Wello/Models/HydrationLog.swift`, après la propriété `coefficient` (ligne 20), ajouter :

```swift
    /// UUID de la `PriseWatch` d'origine, pour les prises saisies au poignet (dédup WCSession).
    /// nil pour toute autre source. Défaut inline = migration légère SwiftData.
    var watchUUID: UUID? = nil
```

Et étendre l'`init` pour l'accepter (paramètre optionnel, défaut `nil`), après `coefficient` :

```swift
    init(amountML: Int, loggedAt: Date = .now, source: String = "app",
         healthKitUUID: UUID? = nil,
         drinkType: String = "water", coefficient: Double = 1.0,
         watchUUID: UUID? = nil) {
        self.amountML = amountML
        self.loggedAt = loggedAt
        self.source = source
        self.healthKitUUID = healthKitUUID
        self.drinkType = drinkType
        self.coefficient = coefficient
        self.watchUUID = watchUUID
    }
```

- [ ] **Step 2 : Protocole `WatchSyncing`**

Dans `Wello/Wello/Services/ServiceProtocols.swift`, importer WelloKit en tête si absent
(`import WelloKit` est déjà présent ligne 2) puis ajouter à la fin du fichier :

```swift

/// Pont WatchConnectivity côté iPhone : pousse l'état d'hydratation vers la Watch.
/// La réception des prises Watch passe par une closure branchée à l'app (cf. WelloApp).
protocol WatchSyncing: Sendable {
    /// Pousse le dernier état (mirroir coalescé). No-op si aucune Watch n'est jumelée.
    func pousser(_ snapshot: WatchSyncSnapshot)
}
```

- [ ] **Step 3 : Mock `WatchSyncing`**

Dans `Wello/Wello/Services/Mocks.swift`, ajouter un mock no-op (style des mocks existants) :

```swift
/// Mock du pont Watch : ne fait rien (previews, tests, appareils sans Watch).
struct MockWatchSync: WatchSyncing {
    func pousser(_ snapshot: WatchSyncSnapshot) {}
}
```

> Vérifier la présence de `import WelloKit` en tête de `Mocks.swift` (sinon l'ajouter) :
> `WatchSyncSnapshot` y est référencé.

- [ ] **Step 4 : Type-check iOS**

Run la commande de type-check complète (voir `CLAUDE.md`).
Expected: `TYPECHECK_OK` (0 erreur).

- [ ] **Step 5 : Commit**

```bash
git add Wello/Wello/Models/HydrationLog.swift Wello/Wello/Services/ServiceProtocols.swift \
  Wello/Wello/Services/Mocks.swift
git commit -m "feat(app): HydrationLog.watchUUID + protocole WatchSyncing (+ mock)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4 : `HydrationStore` — snapshot Watch + ingestion + hooks (app)

**Files:**
- Modify: `Wello/Wello/Services/HydrationStore.swift`

- [ ] **Step 1 : Injecter la dépendance `watchSync`**

Dans `HydrationStore`, ajouter une propriété stockée (après `notifications`) :

```swift
    private let watchSync: WatchSyncing
```

et un paramètre d'`init` (défaut = mock, pour ne pas casser les appels existants/preview), avant
`rappelsAdaptatifsDébloqués` :

```swift
         watchSync: WatchSyncing = MockWatchSync(),
```

avec l'affectation correspondante dans le corps de l'`init` :

```swift
        self.watchSync = watchSync
```

- [ ] **Step 2 : Construire et pousser le snapshot Watch**

Juste avant `private func rechargerWidgets()` (ligne ~334), insérer :

```swift
    /// Construit le mirroir d'état destiné à la Watch à partir de l'objectif/consommé du jour,
    /// du profil minimal et des `id` de prises Watch déjà enregistrées (acquittées).
    private func snapshotWatch() -> WatchSyncSnapshot {
        let profil = profilCourant()
        let début = Calendar.current.startOfDay(for: .now)
        let desc = FetchDescriptor<HydrationLog>(
            predicate: #Predicate { $0.loggedAt >= début && $0.watchUUID != nil })
        let acquittés = ((try? modelContext.fetch(desc)) ?? []).compactMap(\.watchUUID)
        return WatchSyncSnapshot(
            objectifML: breakdown?.totalML ?? 0,
            consomméML: consomméAujourdhui(),
            quickAdds: profil.quickAdds,
            configuré: breakdown != nil,
            sexeRaw: profil.sexe?.rawValue,
            etatPhysioRaw: profil.etatPhysio == .aucun ? nil : profil.etatPhysio.rawValue,
            renalBonusML: profil.renalBonusEffectifML,
            activitySensitivity: profil.activitySensitivity,
            weatherSensitivity: profil.weatherSensitivity,
            manualAdjustmentML: profil.manualAdjustmentML,
            acquittés: acquittés,
            générémLe: .now)
    }

    /// Pousse l'état courant vers la Watch (à appeler après toute mutation, comme `rechargerWidgets`).
    private func pousserSnapshotWatch() {
        watchSync.pousser(snapshotWatch())
    }

```

- [ ] **Step 3 : Ingérer une prise reçue de la Watch**

Juste après `pousserSnapshotWatch()` (toujours avant `rechargerWidgets`), ajouter :

```swift
    /// Enregistre une prise reçue de la Watch (déduplication par `watchUUID`). Écrit l'eau dans
    /// Santé.app (l'iPhone reste l'unique écrivain HealthKit), replanifie les rappels, recharge
    /// widgets + Watch (avec l'`id` désormais acquitté).
    func enregistrerPriseDistante(_ prise: PriseWatch) async {
        let id = prise.id
        let déjàVue = FetchDescriptor<HydrationLog>(predicate: #Predicate { $0.watchUUID == id })
        if let existe = try? modelContext.fetch(déjàVue), !existe.isEmpty {
            pousserSnapshotWatch()   // déjà enregistrée : re-acquitter suffit
            return
        }
        let entrée = HydrationLog(amountML: prise.amountML, loggedAt: prise.loggedAt, source: "watch",
                                  drinkType: "water", coefficient: 1.0, watchUUID: id)
        modelContext.insert(entrée)
        if entrée.effectiveML > 0 { await healthKit.écrireEau(ml: entrée.effectiveML, date: entrée.loggedAt) }
        if let objectif = breakdown?.totalML {
            await planifierSelonPalier(objectifML: objectif)
        }
        rechargerWidgets()
        pousserSnapshotWatch()
    }

```

- [ ] **Step 4 : Appeler `pousserSnapshotWatch()` après chaque mutation**

Ajouter `pousserSnapshotWatch()` juste après chaque `rechargerWidgets()` existant dans :
`refreshToday(force:)`, `log(...)`, `annulerDernièrePrise()`, `supprimer(_:)`.

> Repère : 4 sites appellent déjà `rechargerWidgets()`. Doubler chacun avec `pousserSnapshotWatch()`.

- [ ] **Step 5 : Type-check iOS**

Run la commande de type-check complète.
Expected: `TYPECHECK_OK` (0 erreur).

- [ ] **Step 6 : Commit**

```bash
git add Wello/Wello/Services/HydrationStore.swift
git commit -m "feat(app): HydrationStore — mirroir Watch + ingestion des prises (WCSession)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5 : `WatchConnectivityService` + câblage `WelloApp` (app)

**Files:**
- Create: `Wello/Wello/Services/WatchConnectivityService.swift`
- Modify: `Wello/Wello/App/WelloApp.swift`

- [ ] **Step 1 : Créer le service iPhone**

Create `Wello/Wello/Services/WatchConnectivityService.swift` :

```swift
import Foundation
import WatchConnectivity
import WelloKit

/// Pont WatchConnectivity côté iPhone. Pousse le mirroir d'état (`updateApplicationContext`,
/// coalescé) et reçoit les prises saisies au poignet (`transferUserInfo`) qu'il relaie via
/// `onPriseDistante`. Dégrade silencieusement si aucune Watch n'est jumelée/supportée.
///
/// `@unchecked Sendable` : `WCSession` est thread-safe ; l'unique état mutable (`onPriseDistante`)
/// est fixé une fois au démarrage.
final class WatchConnectivityService: NSObject, WatchSyncing, @unchecked Sendable {
    /// Branché par l'app : appelé à chaque prise reçue de la Watch.
    var onPriseDistante: (@Sendable (PriseWatch) -> Void)?

    private let session: WCSession?

    override init() {
        session = WCSession.isSupported() ? .default : nil
        super.init()
        session?.delegate = self
        session?.activate()
    }

    func pousser(_ snapshot: WatchSyncSnapshot) {
        guard let session, session.activationState == .activated else { return }
        try? session.updateApplicationContext(snapshot.dictionnaire())
    }
}

extension WatchConnectivityService: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState,
                 error: Error?) {}

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        if let prise = PriseWatch(dictionnaire: userInfo) { onPriseDistante?(prise) }
    }

    // Requis sur iOS (gestion du changement de Watch jumelée).
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
```

- [ ] **Step 2 : Câbler `WelloApp`**

Dans `Wello/Wello/App/WelloApp.swift`, `init()` :

a) Après la création de `entitlements`, créer le service Watch :

```swift
        let watchSync = WatchConnectivityService()
```

b) Passer `watchSync: watchSync` au `HydrationStore(...)` (nouvel argument, avant
`rappelsAdaptatifsDébloqués`).

c) Après l'affectation `_store = State(initialValue: store)`, brancher la réception :

```swift
        watchSync.onPriseDistante = { [store] prise in
            Task { @MainActor in await store.enregistrerPriseDistante(prise) }
        }
```

> `store` est une classe `@MainActor @Observable` ; la capture forte est sûre (l'app le retient
> pour toute la session). L'ingestion s'exécute sur le `MainActor` (store `@MainActor`).

- [ ] **Step 3 : Type-check iOS**

Run la commande de type-check complète.
Expected: `TYPECHECK_OK`. `WatchConnectivity` est dans le SDK iOS du simulateur.

- [ ] **Step 4 : Commit**

```bash
git add Wello/Wello/Services/WatchConnectivityService.swift Wello/Wello/App/WelloApp.swift
git commit -m "feat(app): WatchConnectivityService — push mirroir + réception des prises Watch

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6 : Sources de l'app Watch (cible Xcode watchOS)

Cette tâche fournit **toutes** les sources de l'app Watch. La création de la cible, la capability
HealthKit et la membership sont des étapes manuelles (Task 7). Les fichiers vivent dans
`Wello/WelloWatch/`.

**Files:**
- Create: `Wello/WelloWatch/HealthKitWatchService.swift`
- Create: `Wello/WelloWatch/WatchConnectivityClient.swift`
- Create: `Wello/WelloWatch/WatchStore.swift`
- Create: `Wello/WelloWatch/WatchMainView.swift`
- Create: `Wello/WelloWatch/WelloWatchApp.swift`

- [ ] **Step 1 : `HealthKitWatchService.swift`**

```swift
import Foundation
import HealthKit

/// Lecture HealthKit minimale côté Watch : énergie active du jour (pour le recalcul autonome de
/// l'objectif). Dégrade à 0 si indisponible/refusé. L'écriture de l'eau reste côté iPhone.
final class HealthKitWatchService: @unchecked Sendable {
    private let store = HKHealthStore()
    private let energyType = HKQuantityType(.activeEnergyBurned)

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        try? await store.requestAuthorization(toShare: [], read: [energyType])
    }

    /// Énergie active brûlée aujourd'hui (kcal). 0 si indisponible/refusé.
    func énergieActiveDuJour() async -> Double {
        guard HKHealthStore.isHealthDataAvailable() else { return 0 }
        let début = Calendar.current.startOfDay(for: .now)
        let prédicat = HKQuery.predicateForSamples(withStart: début, end: .now)
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: energyType, quantitySamplePredicate: prédicat,
                                      options: .cumulativeSum) { _, stats, _ in
                cont.resume(returning: stats?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0)
            }
            store.execute(q)
        }
    }
}
```

- [ ] **Step 2 : `WatchConnectivityClient.swift`**

```swift
import Foundation
import WatchConnectivity
import WelloKit

/// Pont WatchConnectivity côté Watch : reçoit le mirroir d'état (`applicationContext`) et envoie
/// les prises (`transferUserInfo`, file à livraison garantie même iPhone injoignable).
final class WatchConnectivityClient: NSObject, @unchecked Sendable {
    /// Branché par le `WatchStore` : appelé à chaque snapshot reçu de l'iPhone.
    var onSnapshot: (@Sendable (WatchSyncSnapshot) -> Void)?

    private let session: WCSession?

    override init() {
        session = WCSession.isSupported() ? .default : nil
        super.init()
        session?.delegate = self
        session?.activate()
    }

    /// Envoie une prise à l'iPhone (mise en file si injoignable).
    func envoyer(_ prise: PriseWatch) {
        session?.transferUserInfo(prise.dictionnaire())
    }
}

extension WatchConnectivityClient: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState,
                 error: Error?) {
        // Au démarrage, l'iPhone a peut-être déjà déposé un applicationContext : le consommer.
        let ctx = session.receivedApplicationContext
        if let snap = WatchSyncSnapshot(dictionnaire: ctx) { onSnapshot?(snap) }
    }

    func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        if let snap = WatchSyncSnapshot(dictionnaire: context) { onSnapshot?(snap) }
    }
}
```

- [ ] **Step 3 : `WatchStore.swift`**

```swift
import Foundation
import SwiftUI
import WelloKit

/// Orchestrateur de l'app Watch. Détient l'`ÉtatHydratationWatch` (réconciliation pure), persiste
/// la file de prises locales (survit au relaunch), pousse les prises à l'iPhone et applique les
/// snapshots reçus. Source d'affichage : `consommé`/`objectif`/`progress`.
@MainActor
@Observable
final class WatchStore {
    private(set) var état = ÉtatHydratationWatch()

    private let connectivity: WatchConnectivityClient
    private let healthKit: HealthKitWatchService
    private let défauts = UserDefaults.standard
    private static let cléPrises = "wello.watch.prisesLocales"

    init(connectivity: WatchConnectivityClient = .init(),
         healthKit: HealthKitWatchService = .init()) {
        self.connectivity = connectivity
        self.healthKit = healthKit
        état = ÉtatHydratationWatch(prisesLocales: chargerPrises())
        connectivity.onSnapshot = { [weak self] snap in
            Task { @MainActor in self?.appliquer(snap) }
        }
    }

    var configuré: Bool { état.configuré }
    var progress: WidgetProgress { état.progress }
    var quickAdds: [Int] { état.quickAdds }

    /// Demande l'accès HealthKit et lit l'énergie active (recalcul autonome de l'objectif).
    func démarrer() async {
        await healthKit.requestAuthorization()
        état.mettreÀJourÉnergie(await healthKit.énergieActiveDuJour())
    }

    /// Ajoute une prise : affichage optimiste + envoi à l'iPhone + persistance.
    func ajouter(ml: Int) {
        let prise = PriseWatch(amountML: ml)
        état.ajouterPrise(prise)
        connectivity.envoyer(prise)
        sauvegarderPrises()
    }

    /// Annule la dernière prise locale non encore acquittée (no-op sinon).
    func annulerDernière() {
        état.annulerDernièreEnAttente()
        sauvegarderPrises()
    }

    private func appliquer(_ snap: WatchSyncSnapshot) {
        état.appliquer(snap)
        sauvegarderPrises()   // purge des acquittées persistée
    }

    // MARK: Persistance de la file locale

    private func chargerPrises() -> [PriseWatch] {
        guard let data = défauts.data(forKey: Self.cléPrises),
              let prises = try? JSONDecoder().decode([PriseWatch].self, from: data) else { return [] }
        return prises
    }

    private func sauvegarderPrises() {
        let data = try? JSONEncoder().encode(état.prisesLocales)
        défauts.set(data, forKey: Self.cléPrises)
    }
}
```

- [ ] **Step 4 : `WatchMainView.swift`**

```swift
import SwiftUI
import WelloKit

/// Teintes minimales (dupliquées pour découpler la Watch du thème app, comme le widget).
private enum WatchTheme {
    static let accent = Color(red: 0.31, green: 0.69, blue: 0.90)
    static let accentDeep = Color(red: 0.18, green: 0.55, blue: 0.79)
    static let gradient = LinearGradient(colors: [accent, accentDeep],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// Anneau de progression (repris du widget).
private struct Ring: View {
    let fraction: Double
    var body: some View {
        ZStack {
            Circle().stroke(WatchTheme.accent.opacity(0.18), lineWidth: 9)
            Circle()
                .trim(from: 0, to: max(0.001, fraction))
                .stroke(WatchTheme.gradient, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

/// Écran principal de l'app Watch : jauge + 3 boutons d'ajout rapide + annuler.
struct WatchMainView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        ScrollView {
            if store.configuré {
                VStack(spacing: 10) {
                    ZStack {
                        Ring(fraction: store.progress.fraction)
                        VStack(spacing: 1) {
                            Text(store.progress.libelléPourcent)
                                .font(.system(.title3, design: .rounded).weight(.bold))
                                .foregroundStyle(WatchTheme.accentDeep)
                            Text(store.progress.libelléValeurs)
                                .font(.system(.caption2, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(height: 92)

                    HStack(spacing: 6) {
                        ForEach(store.quickAdds, id: \.self) { ml in
                            Button { store.ajouter(ml: ml) } label: {
                                Text("+\(ml)")
                                    .font(.system(.footnote, design: .rounded).weight(.bold))
                                    .frame(maxWidth: .infinity)
                            }
                            .tint(WatchTheme.accent)
                        }
                    }

                    Button("Annuler", systemImage: "arrow.uturn.backward") {
                        store.annulerDernière()
                    }
                    .font(.caption2)
                    .tint(.secondary)
                }
                .padding(.horizontal, 4)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "drop").font(.title).foregroundStyle(WatchTheme.accent)
                    Text("Ouvre Wello sur l'iPhone")
                        .font(.footnote).multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
        }
        .navigationTitle("Wello")
        .task { await store.démarrer() }
    }
}
```

- [ ] **Step 5 : `WelloWatchApp.swift` (`@main`)**

```swift
import SwiftUI

@main
struct WelloWatchApp: App {
    @State private var store = WatchStore()

    var body: some Scene {
        WindowGroup {
            NavigationStack { WatchMainView() }
                .environment(\.locale, Locale(identifier: "fr_FR"))
                .environment(store)
        }
    }
}
```

- [ ] **Step 6 : Commit**

```bash
git add Wello/WelloWatch/
git commit -m "feat(watch): app watchOS — jauge, ajout rapide, sync WCSession + HealthKit

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 7 : Intégration Xcode + documentation

Étapes manuelles dans Xcode (non automatisables en CLI) puis docs.

**Files:**
- Modify: `README.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1 : Créer la cible Watch (manuel)**

1. File ▸ New ▸ Target ▸ **watchOS ▸ App**, nom **WelloWatch**, interface **SwiftUI**,
   *Include Notification Scene* **décoché**.
2. Supprimer les fichiers d'exemple générés ; **ajouter** à la cible les 5 fichiers de
   `Wello/WelloWatch/`.
3. Déploiement minimum de la cible Watch : **watchOS 10.0**.
4. Lier le package **WelloKit** à la cible WelloWatch (Frameworks and Libraries).

- [ ] **Step 2 : Capability HealthKit + Info.plist (manuel)**

Sur la cible **WelloWatch** : Signing & Capabilities ▸ + Capability ▸ **HealthKit** ;
Info.plist ▸ `NSHealthShareUsageDescription` = « Wello lit ton énergie active pour ajuster ton
objectif d'hydratation au poignet. » (lecture seule, pas de `NSHealthUpdateUsageDescription`).

- [ ] **Step 3 : Ajouter le service iPhone à la cible app (manuel)**

`WatchConnectivityService.swift` étant dans `Wello/Wello/Services/`, il est pris par les groupes
synchronisés ; vérifier qu'il appartient bien à la cible **Wello** (app iPhone). `WatchConnectivity`
est dans le SDK iOS (aucune capability).

- [ ] **Step 4 : Test sur simulateurs jumelés / appareils (manuel)**

1. Lancer l'app iPhone (renseigner le sexe → objectif calculé) ; lancer l'app Watch.
2. La jauge Watch affiche objectif + consommé (mirroir reçu).
3. **+250** au poignet → la prise apparaît dans l'app iPhone (au `foreground`) et dans Santé.app ;
   la jauge Watch se réconcilie (prise acquittée, pas de double compte).
4. Une prise saisie sur l'iPhone met à jour la jauge Watch.
5. **Hors-ligne** : iPhone en mode avion → un tap fait bouger la jauge Watch ; à la reconnexion la
   prise remonte et se réconcilie.
6. HealthKit Watch refusé → l'app reste utilisable (objectif = celui poussé).

- [ ] **Step 5 : `README` — app Watch livrée**

Dans `README.md`, après la section « Widget iOS (Phase 2 — livré) », ajouter :

```
## App Apple Watch (Phase 2 — livrée)

App Watch autonome : jauge de progression + ajout rapide d'eau au poignet, utilisable hors-ligne.
Synchronisation **sans CloudKit** entre deux appareils via **WatchConnectivity** : l'iPhone pousse
l'objectif/consommé du jour (mirroir coalescé) ; la Watch met ses prises en file (livraison garantie)
et les envoie à l'iPhone, **unique écrivain HealthKit** (déduplication par `watchUUID`, pas de double
compte). La Watch lit l'énergie active (HealthKit) pour faire monter la part « activité » de
l'objectif en séance, même iPhone absent. **Complication de cadran** : prévue dans un second temps.
```

Mettre à jour la ligne « watchOS / complication Watch restent prévus en Phase 2 » de la section
widget pour ne plus mentionner l'app Watch comme à faire (seule la complication reste).

- [ ] **Step 6 : `CLAUDE.md` — carte projet + étapes Xcode**

a) Sous « Carte du projet », ajouter :

```
- `Wello/WelloWatch/` — app watchOS (Phase 2) : `WatchStore` + vues, sync via WatchConnectivity
  (mirroir iPhone→Watch + prises Watch→iPhone) et HealthKit en lecture. Aucun store partagé
  (deux appareils) ; logique de réconciliation pure dans WelloKit (`ÉtatHydratationWatch`).
```

b) Sous « Étapes Xcode manuelles », ajouter :

```
Cible watchOS `WelloWatch` : membership des sources `Wello/WelloWatch/`, lien WelloKit, capability
HealthKit + `NSHealthShareUsageDescription` (lecture énergie active). `WatchConnectivityService.swift`
doit appartenir à la cible app iPhone. Pas de capability WatchConnectivity (SDK).
```

- [ ] **Step 7 : Vérification finale**

```bash
cd WelloKit && swift test && cd ..
```
Expected: tout vert. Puis la commande de type-check **app** complète (`CLAUDE.md`) → `TYPECHECK_OK`.

- [ ] **Step 8 : Commit**

```bash
git add README.md CLAUDE.md
git commit -m "docs: app Apple Watch Phase 2 (WatchConnectivity, sync, étapes Xcode)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Vérification finale

- [ ] `cd WelloKit && swift test` → vert (`WatchSync` + `ÉtatHydratationWatch` ajoutés, suite complète OK).
- [ ] Type-check iOS **app** complet → `TYPECHECK_OK` (modèle `watchUUID`, `WatchSyncing`+mock,
  `WatchConnectivityService`, hooks store, `WelloApp`).
- [ ] Xcode (manuel) : app Watch jumelée — mirroir reçu, +250 au poignet persiste côté iPhone +
  Santé.app sans double compte, prise iPhone met à jour la Watch, mode avion → jauge bouge puis
  se réconcilie.

## Self-Review (effectuée)

**Couverture de la spec :**
- Sync Watch→iPhone via WCSession `transferUserInfo` (source de vérité, UUID) → Task 4/5/6 ✅
- Mirroir iPhone→Watch via `updateApplicationContext` après chaque mutation → Task 4/5 ✅
- Réconciliation pure (consommé = autoritaire + non acquittés ; objectif = max poussé/recalculé) →
  Task 2 (`ÉtatHydratationWatch`), testée CLI ✅
- Codecs dictionnaire plist-safe (WCSession) → Task 1, testés CLI ✅
- Unique écrivain HealthKit = iPhone ; dédup par `watchUUID` → Task 3 (champ) + Task 4 (ingestion) ✅
- Recalcul autonome via WelloKit + énergie active Watch → Task 2 + Task 6 (`HealthKitWatchService`) ✅
- Offline (file garantie + jauge optimiste persistée) → Task 6 (`WatchStore` + `transferUserInfo`) ✅
- App Watch (jauge + ajout rapide + annuler) → Task 6 (`WatchMainView`) ✅
- Hors périmètre (complication, écriture HK Watch, boisson, annulation d'une prise synchronisée) :
  non implémentés ✅

**Placeholders :** aucun — chaque étape contient le code/texte réel.

**Cohérence des types :** `PriseWatch(id:amountML:loggedAt:)` + `dictionnaire()`/`init?(dictionnaire:)`
(Task 1) utilisés par `transferUserInfo` (Task 5/6) et `enregistrerPriseDistante` (Task 4) ;
`WatchSyncSnapshot` (Task 1) construit par `snapshotWatch()` (Task 4), poussé par
`WatchConnectivityService.pousser` (Task 5), décodé côté Watch (Task 6) et réduit par
`ÉtatHydratationWatch.appliquer` (Task 2) ; `WatchSyncing.pousser` (Task 3) implémenté par le service
(Task 5) et appelé par le store (Task 4) ; `HydrationLog(... watchUUID:)` (Task 3) écrit par
`enregistrerPriseDistante` (Task 4) ; `WidgetProgress` réutilisé par `ÉtatHydratationWatch.progress`
(Task 2) et `WatchMainView` (Task 6).
</content>
