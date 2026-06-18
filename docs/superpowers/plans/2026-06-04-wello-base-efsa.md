# Base d'hydratation EFSA (par sexe) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remplacer la base `poids × 35 ml/kg` (qui surestime car c'est une valeur d'eau *totale*) par une base EFSA par sexe (boisson : 2000 ml homme / 1600 ml femme), retirer complètement le poids de l'app, et forcer le choix du sexe à l'onboarding.

**Architecture:** Base par sexe dans `HydrationCalculator` (pur, testé CLI) ; `BiologicalSex` enum pur ; `weightKg`/`WeightResolver`/lecture HealthKit `bodyMass` supprimés ; `sexe` optionnel ajouté à `UserProfile` (migration légère SwiftData) avec gating onboarding. Activité/météo/plancher/plafond inchangés.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, HealthKit, Swift Testing (`swift test`). Patterns existants : logique pure WelloKit, services derrière protocoles + mocks, pattern MV.

**Spec :** `docs/superpowers/specs/2026-06-04-wello-base-efsa-design.md`.

> **Branche :** le repo est sur `main`. Avant la Task 1 : `git checkout -b feat/wello-base-efsa`.
> Les commits utilisent le trailer `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.

**Note de vérification :** tâches WelloKit → `cd WelloKit && swift test`. Tâches app → type-check
iOS hors Xcode (globs : nouveaux fichiers pris automatiquement) :

```bash
rm -rf /tmp/wellomod && mkdir -p /tmp/wellomod
xcrun --sdk iphonesimulator swiftc -emit-module -module-name WelloKit \
  -target arm64-apple-ios17.0-simulator \
  WelloKit/Sources/WelloKit/*.swift WelloKit/Sources/WelloKit/Models/*.swift \
  -emit-module-path /tmp/wellomod/WelloKit.swiftmodule
xcrun --sdk iphonesimulator swiftc -typecheck -D DEBUG \
  -enable-upcoming-feature MemberImportVisibility \
  -target arm64-apple-ios17.0-simulator -I /tmp/wellomod \
  Wello/Wello/App/*.swift Wello/Wello/Models/*.swift \
  Wello/Wello/Services/*.swift Wello/Wello/Views/*.swift && echo TYPECHECK_OK
```

> **Conséquence de design notable :** le besoin physiologique maximal devient
> 2000 (base) + 1000 (activité) + 600 (météo) = **3600 ml < 4000**. Le plafond de sécurité 4000 ml
> n'est donc plus jamais atteint par le besoin physiologique — seulement par un plancher médical
> incohérent (> 4000, que le Profil empêche de toute façon). C'est voulu et reste un garde-fou.

---

## File Structure

**Créés :**
- `WelloKit/Sources/WelloKit/Models/BiologicalSex.swift` — enum pur du sexe + `label`.

**Modifiés :**
- `WelloKit/Sources/WelloKit/Models/CalculatorInputs.swift` — `weightKg` → `sex`.
- `WelloKit/Sources/WelloKit/HydrationCalculator.swift` — base par sexe (constantes).
- `WelloKit/Tests/WelloKitTests/HydrationCalculatorTests.swift` — réécrit pour `sex`.
- `Wello/Wello/Models/UserProfile.swift` — retire `weightKg`, ajoute `sexe`.
- `Wello/Wello/Services/ServiceProtocols.swift` — retire `dernierPoids`.
- `Wello/Wello/Services/HealthKitService.swift` — retire `dernierPoids`/`bodyMass`.
- `Wello/Wello/Services/Mocks.swift` — retire `poids`/`dernierPoids`.
- `Wello/Wello/Services/HydrationStore.swift` — gating sexe, inputs `sex`, `ÉtatServices`.
- `Wello/Wello/Views/PreviewSupport.swift` — profil avec `sexe`.
- `Wello/Wello/Views/ProfileView.swift` — Picker sexe, diagnostic.
- `Wello/Wello/Views/BreakdownCard.swift` — libellé/icône base.
- `Wello/Wello/Views/OnboardingView.swift` — étape choix du sexe.
- `Wello/Wello/Views/RootView.swift` — gating onboarding sur `sexe`.
- `README.md`, `CLAUDE.md` — docs.

**Supprimés :**
- `WelloKit/Sources/WelloKit/WeightResolver.swift`
- `WelloKit/Tests/WelloKitTests/WeightResolverTests.swift`

---

## Task 1 : Base EFSA par sexe (WelloKit, TDD)

**Files:**
- Create: `WelloKit/Sources/WelloKit/Models/BiologicalSex.swift`
- Modify: `WelloKit/Sources/WelloKit/Models/CalculatorInputs.swift`
- Modify: `WelloKit/Sources/WelloKit/HydrationCalculator.swift`
- Test: `WelloKit/Tests/WelloKitTests/HydrationCalculatorTests.swift` (réécriture complète)

- [ ] **Step 1 : Réécrire le fichier de tests (rouge)**

Remplacer **tout** le contenu de `WelloKit/Tests/WelloKitTests/HydrationCalculatorTests.swift` par :

```swift
import Testing
@testable import WelloKit

@Suite("HydrationCalculator")
struct HydrationCalculatorTests {

    let calc = HydrationCalculator()

    @Test("Base homme = 2000 ml (EFSA), sans bonus")
    func baseHomme() {
        let inputs = CalculatorInputs(sex: .homme, activeEnergyKcal: 0, weather: nil, medicalFloorML: 1500)
        let r = calc.calculate(inputs)
        #expect(r.baseML == 2000)
        #expect(r.activityBonusML == 0)
        #expect(r.weatherBonusML == 0)
        #expect(r.totalML == 2000)
        #expect(r.plancherContraignant == false)
        #expect(r.plafondAppliqué == false)
    }

    @Test("Base femme = 1600 ml (EFSA), sans bonus")
    func baseFemme() {
        let inputs = CalculatorInputs(sex: .femme, activeEnergyKcal: 0, weather: nil, medicalFloorML: 1500)
        let r = calc.calculate(inputs)
        #expect(r.baseML == 1600)
        #expect(r.totalML == 1600)
    }

    @Test("Activité : 1 ml par kcal d'énergie active")
    func activitéProportionnelle() {
        let inputs = CalculatorInputs(sex: .homme, activeEnergyKcal: 300, weather: nil, medicalFloorML: 1500)
        let r = calc.calculate(inputs)
        #expect(r.baseML == 2000)
        #expect(r.activityBonusML == 300)
        #expect(r.totalML == 2300)
    }

    @Test("Énergie active arrondie au ml près")
    func activitéArrondie() {
        let inputs = CalculatorInputs(sex: .homme, activeEnergyKcal: 250.6, weather: nil, medicalFloorML: 1500)
        #expect(calc.calculate(inputs).activityBonusML == 251)
    }

    @Test("Activité plafonnée à 1000 ml")
    func activitéPlafonnée() {
        let inputs = CalculatorInputs(sex: .homme, activeEnergyKcal: 1200, weather: nil, medicalFloorML: 1500)
        let r = calc.calculate(inputs)
        #expect(r.activityBonusML == 1000)
        #expect(r.totalML == 3000)           // 2000 + 1000
    }

    @Test("Météo absente (nil) → bonus 0, calcul OK")
    func météoAbsente() {
        let inputs = CalculatorInputs(sex: .homme, activeEnergyKcal: 0, weather: nil, medicalFloorML: 1500)
        let r = calc.calculate(inputs)
        #expect(r.weatherBonusML == 0)
        #expect(r.totalML == 2000)
    }

    @Test("Température ressentie au seuil de confort ou en dessous (≤ 27°C) → bonus 0")
    func ressentiSousConfort() {
        for ressentie in [20.0, 27.0] {
            let w = WeatherSnapshot(apparentTemperatureC: ressentie)
            let inputs = CalculatorInputs(sex: .homme, activeEnergyKcal: 0, weather: w, medicalFloorML: 1500)
            #expect(calc.calculate(inputs).weatherBonusML == 0)
        }
    }

    @Test("Au-dessus du confort : 50 ml par °C ressenti")
    func ressentiLinéaire() {
        // 33°C ressentis → 6°C au-dessus de 27 → 300 ml.
        let w = WeatherSnapshot(apparentTemperatureC: 33)
        let inputs = CalculatorInputs(sex: .homme, activeEnergyKcal: 0, weather: w, medicalFloorML: 1500)
        let r = calc.calculate(inputs)
        #expect(r.weatherBonusML == 300)
        #expect(r.totalML == 2300)
    }

    @Test("Bonus météo plafonné à 600 ml")
    func ressentiPlafonné() {
        // 45°C ressentis → 18 × 50 = 900 → bridé à 600.
        let w = WeatherSnapshot(apparentTemperatureC: 45)
        let inputs = CalculatorInputs(sex: .homme, activeEnergyKcal: 0, weather: w, medicalFloorML: 1500)
        #expect(calc.calculate(inputs).weatherBonusML == 600)
    }

    @Test("physiologicalML = base + activité + météo, indépendant du plancher")
    func besoinPhysiologique() {
        let w = WeatherSnapshot(apparentTemperatureC: 37)   // 10°C au-dessus du confort → +500
        let inputs = CalculatorInputs(sex: .homme, activeEnergyKcal: 330, weather: w, medicalFloorML: 2500)
        let r = calc.calculate(inputs)
        #expect(r.physiologicalML == 2830)   // 2000 + 330 + 500
        #expect(r.totalML == 2830)           // > plancher 2500, donc le physiologique gagne
    }

    @Test("physiologicalML reste sous le total quand le plancher contraint")
    func physiologiqueSousPlancher() {
        let inputs = CalculatorInputs(sex: .femme, activeEnergyKcal: 0, weather: nil, medicalFloorML: 2500)
        let r = calc.calculate(inputs)
        #expect(r.physiologicalML == 1600)
        #expect(r.totalML == 2500)
    }

    @Test("Plancher médical relève l'objectif quand le physiologique est plus bas")
    func plancherContraignant() {
        let inputs = CalculatorInputs(sex: .homme, activeEnergyKcal: 0, weather: nil, medicalFloorML: 2500)
        let r = calc.calculate(inputs)
        #expect(r.totalML == 2500)
        #expect(r.plancherContraignant == true)
        #expect(r.plafondAppliqué == false)
    }

    @Test("Plancher non contraignant quand le physiologique est plus haut")
    func plancherNonContraignant() {
        let inputs = CalculatorInputs(sex: .homme, activeEnergyKcal: 0, weather: nil, medicalFloorML: 1500)
        let r = calc.calculate(inputs)
        #expect(r.totalML == 2000)
        #expect(r.plancherContraignant == false)
    }

    @Test("Besoin physiologique maximal (3600) reste sous le plafond de 4000")
    func physiologiqueMaxSousPlafond() {
        // base 2000 + activité bridée 1000 + météo bridée 600 = 3600.
        let w = WeatherSnapshot(apparentTemperatureC: 50)
        let inputs = CalculatorInputs(sex: .homme, activeEnergyKcal: 2000, weather: w, medicalFloorML: 1500)
        let r = calc.calculate(inputs)
        #expect(r.activityBonusML == 1000)
        #expect(r.weatherBonusML == 600)
        #expect(r.totalML == 3600)
        #expect(r.plafondAppliqué == false)
    }

    @Test("Plafond prime sur un plancher médical incohérent (> 4000)")
    func plafondPrimeSurPlancher() {
        // Plancher 4500 invalide (le Profil l'empêche) : le plafond de sécurité prime.
        let inputs = CalculatorInputs(sex: .homme, activeEnergyKcal: 0, weather: nil, medicalFloorML: 4500)
        let r = calc.calculate(inputs)
        #expect(r.totalML == 4000)
        #expect(r.plafondAppliqué == true)
    }
}
```

- [ ] **Step 2 : Lancer les tests pour vérifier l'échec**

Run: `cd WelloKit && swift test --filter HydrationCalculator`
Expected: FAIL — `cannot find 'BiologicalSex'` / `CalculatorInputs` n'a pas de paramètre `sex`.

- [ ] **Step 3 : Créer `BiologicalSex.swift`**

Create `WelloKit/Sources/WelloKit/Models/BiologicalSex.swift` :

```swift
/// Sexe biologique, base physiologique du besoin en eau (apports de référence EFSA 2010).
public enum BiologicalSex: String, Sendable, CaseIterable {
    case homme
    case femme
    /// Libellé court français pour l'affichage.
    public var label: String { self == .homme ? "Homme" : "Femme" }
}
```

- [ ] **Step 4 : Remplacer `weightKg` par `sex` dans `CalculatorInputs`**

Remplacer **tout** le contenu de `WelloKit/Sources/WelloKit/Models/CalculatorInputs.swift` par :

```swift
/// Entrées du calcul d'objectif d'hydratation. `weather` est optionnel :
/// si la météo est indisponible (réseau/API down), le bonus météo vaut 0.
public struct CalculatorInputs: Sendable, Equatable {
    /// Sexe biologique : fixe la base EFSA (2000 ml homme / 1600 ml femme).
    public let sex: BiologicalSex
    /// Énergie active brûlée à l'effort aujourd'hui (kcal), issue de HealthKit.
    /// Proxy physiologique de la perte sudorale (intensité, pas seulement durée).
    public let activeEnergyKcal: Double
    public let weather: WeatherSnapshot?
    public let medicalFloorML: Int

    public init(sex: BiologicalSex, activeEnergyKcal: Double, weather: WeatherSnapshot?, medicalFloorML: Int) {
        self.sex = sex
        self.activeEnergyKcal = activeEnergyKcal
        self.weather = weather
        self.medicalFloorML = medicalFloorML
    }
}
```

- [ ] **Step 5 : Base par sexe dans `HydrationCalculator`**

Dans `WelloKit/Sources/WelloKit/HydrationCalculator.swift` :

a) Remplacer le bloc `Constantes` par (retire `mlParKg`, ajoute les deux bases EFSA) :

```swift
    /// Constantes médicales/algorithmiques nommées (cf. spec).
    public enum Constantes {
        /// Cible de boisson EFSA 2010 (eau totale 2,5 L / 2,0 L, dont ~80 % via les boissons).
        public static let baseHommeML = 2000
        public static let baseFemmeML = 1600
        /// ml d'eau par kcal d'énergie active. Base scientifique : évaporer 1 mL de sueur
        /// dissipe ~0,58 kcal ; à l'effort ~75-80 % de l'énergie devient chaleur, dissipée
        /// majoritairement par la sueur → ~1 mL/kcal (coefficient conservateur).
        public static let mlParKcal = 1.0
        public static let plafondActivité = 1000
        /// Température ressentie (°C) en dessous de laquelle aucun bonus météo (zone de confort).
        public static let seuilConfortRessentiC = 27.0
        /// ml d'eau supplémentaires par °C ressenti au-dessus du seuil de confort.
        public static let mlParDegréRessenti = 50.0
        /// Plafond du bonus météo (≈ +12°C ressentis au-dessus du confort).
        public static let plafondMétéo = 600
        /// Plafond de sécurité global : on n'affiche jamais d'objectif supérieur.
        public static let plafondGlobal = 4000
    }
```

b) Remplacer la ligne `let base = Int((inputs.weightKg * Constantes.mlParKg).rounded())` par :

```swift
        let base = inputs.sex == .homme ? Constantes.baseHommeML : Constantes.baseFemmeML
```

- [ ] **Step 6 : Lancer les tests pour vérifier le succès**

Run: `cd WelloKit && swift test --filter HydrationCalculator`
Expected: PASS (15 tests).

- [ ] **Step 7 : Commit**

```bash
git add WelloKit/Sources/WelloKit/Models/BiologicalSex.swift \
  WelloKit/Sources/WelloKit/Models/CalculatorInputs.swift \
  WelloKit/Sources/WelloKit/HydrationCalculator.swift \
  WelloKit/Tests/WelloKitTests/HydrationCalculatorTests.swift
git commit -m "feat(kit): base d'hydratation EFSA par sexe (remplace per-kg)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2 : Supprimer `WeightResolver` (WelloKit)

**Files:**
- Delete: `WelloKit/Sources/WelloKit/WeightResolver.swift`
- Delete: `WelloKit/Tests/WelloKitTests/WeightResolverTests.swift`

- [ ] **Step 1 : Supprimer les deux fichiers**

```bash
rm WelloKit/Sources/WelloKit/WeightResolver.swift
rm WelloKit/Tests/WelloKitTests/WeightResolverTests.swift
```

- [ ] **Step 2 : Vérifier que le package compile et que tous les tests passent**

Run: `cd WelloKit && swift test`
Expected: PASS (suite `WeightResolver` disparue ; `HydrationCalculator`, `HydrationStats`,
`Premium` au vert). Aucune référence résiduelle à `résoudrePoids` dans le package
(elle n'était utilisée que côté app, traité en Task 3).

- [ ] **Step 3 : Commit**

```bash
git add -A WelloKit/
git commit -m "refactor(kit): supprime WeightResolver (poids retiré du calcul)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3 : Refactor app coordonné (modèle, services, store)

Cette tâche fait **tous** les changements app interdépendants imposés par les nouvelles signatures
(suppression `weightKg`, `dernierPoids`, `poidsDepuisSanté` ; `CalculatorInputs.sex`). Le type-check
n'est attendu vert qu'**à la fin** de la tâche.

**Files:**
- Modify: `Wello/Wello/Models/UserProfile.swift`
- Modify: `Wello/Wello/Services/ServiceProtocols.swift`
- Modify: `Wello/Wello/Services/HealthKitService.swift`
- Modify: `Wello/Wello/Services/Mocks.swift`
- Modify: `Wello/Wello/Services/HydrationStore.swift`
- Modify: `Wello/Wello/Views/PreviewSupport.swift`

- [ ] **Step 1 : `UserProfile` — retirer le poids, ajouter le sexe**

Remplacer **tout** le contenu de `Wello/Wello/Models/UserProfile.swift` par :

```swift
import Foundation
import SwiftData
import WelloKit

/// Profil unique de l'utilisateur (app mono-utilisateur).
@Model
final class UserProfile {
    /// Plancher médical fixe (ex. 2500 ml) — suivi de calculs rénaux calciques.
    var medicalFloorML: Int
    var remindersEnabled: Bool
    /// Sexe biologique pour la base EFSA. Stocké en brut (String?) pour la migration légère
    /// SwiftData ; nil = pas encore renseigné (force l'onboarding). Exposé via `sexe`.
    var sexeRaw: String? = nil
    /// Montants des 3 boutons d'ajout rapide (personnalisables). Défauts inline pour
    /// la migration légère SwiftData.
    var quickAdd1: Int = 150
    var quickAdd2: Int = 250
    var quickAdd3: Int = 500
    var updatedAt: Date

    /// Les 3 montants rapides dans l'ordre, pour itération en UI.
    var quickAdds: [Int] { [quickAdd1, quickAdd2, quickAdd3] }

    /// Sexe biologique, ou nil si non renseigné.
    var sexe: BiologicalSex? {
        get { sexeRaw.flatMap(BiologicalSex.init(rawValue:)) }
        set { sexeRaw = newValue?.rawValue }
    }

    init(medicalFloorML: Int = 2500, remindersEnabled: Bool = true,
         quickAdd1: Int = 150, quickAdd2: Int = 250, quickAdd3: Int = 500,
         updatedAt: Date = .now) {
        self.medicalFloorML = medicalFloorML
        self.remindersEnabled = remindersEnabled
        self.quickAdd1 = quickAdd1
        self.quickAdd2 = quickAdd2
        self.quickAdd3 = quickAdd3
        self.updatedAt = updatedAt
    }
}
```

- [ ] **Step 2 : `ServiceProtocols` — retirer `dernierPoids`**

Dans `Wello/Wello/Services/ServiceProtocols.swift` :

a) Retirer ces deux lignes du protocole `HealthKitServicing` :

```swift
    /// Dernier poids connu en kg, ou nil si indisponible/refusé.
    func dernierPoids() async -> Double?
```

b) Remplacer le commentaire de `requestAuthorization` :

```swift
    /// Demande les autorisations (lecture workouts+énergie, écriture eau). Sans effet si déjà décidé.
    func requestAuthorization() async
```

- [ ] **Step 3 : `HealthKitService` — retirer `dernierPoids` et la lecture `bodyMass`**

Dans `Wello/Wello/Services/HealthKitService.swift` :

a) Supprimer la ligne `private let bodyMassType = HKQuantityType(.bodyMass)`.

b) Remplacer le set de lecture dans `requestAuthorization` par (sans `bodyMassType`) :

```swift
        let read: Set<HKObjectType> = [workoutType, waterType, energyType]
```

c) Supprimer entièrement la fonction `dernierPoids()` (les lignes `func dernierPoids() async -> Double? { ... }`).

- [ ] **Step 4 : `Mocks` — retirer le poids du mock HealthKit**

Dans `Wello/Wello/Services/Mocks.swift`, dans `MockHealthKitService`, supprimer la ligne
`var poids: Double? = 78` et la ligne `func dernierPoids() async -> Double? { poids }`.

- [ ] **Step 5 : `HydrationStore` — `ÉtatServices` + `refreshToday`**

Dans `Wello/Wello/Services/HydrationStore.swift` :

a) Remplacer le struct `ÉtatServices` par (retire `poidsDepuisSanté`) :

```swift
struct ÉtatServices: Sendable {
    var localisationDisponible = false
    var météoDisponible = false
    var notificationsAutorisées = false

    /// Tout fonctionne : on masque alors le diagnostic.
    var tousOK: Bool { météoDisponible && notificationsAutorisées }
}
```

b) Remplacer la fonction `refreshToday(force:)` par :

```swift
    /// Recalcule l'objectif du jour à partir du sexe (base EFSA), de l'énergie active et de la
    /// météo (best-effort), puis met à jour (upsert) le DailyGoal du jour. Replanifie les rappels.
    /// Throttlé (10 min, même jour) ; `force` court-circuite. Si le sexe n'est pas renseigné,
    /// aucun objectif n'est calculé (choix forcé à l'onboarding).
    func refreshToday(force: Bool = false) async {
        if !force, let dernier = dernierRefresh,
           Date.now.timeIntervalSince(dernier) < Self.fenêtreRefresh,
           Calendar.current.isDate(dernier, inSameDayAs: .now) {
            return
        }

        let profil = profilCourant()
        guard let sexe = profil.sexe else {
            breakdown = nil   // pas d'objectif tant que le sexe n'est pas renseigné
            return
        }
        dernierRefresh = .now

        // Demande d'autorisation HealthKit une seule fois par session (inutile ensuite).
        if !autorisationDemandée {
            await healthKit.requestAuthorization()
            autorisationDemandée = true
        }
        let énergie = await healthKit.énergieActiveDuJour()

        let (snapshot, localisationOK) = await météoActuelle()
        météoIndisponible = (snapshot == nil)

        let inputs = CalculatorInputs(sex: sexe, activeEnergyKcal: énergie,
                                      weather: snapshot, medicalFloorML: profil.medicalFloorML)
        let resultat = calculator.calculate(inputs)
        breakdown = resultat
        upsertDailyGoal(resultat)

        await importerEauHealthKit()

        let notifsOK = await notifications.autorisationAccordée()
        étatServices = ÉtatServices(localisationDisponible: localisationOK,
                                    météoDisponible: snapshot != nil,
                                    notificationsAutorisées: notifsOK)

        if profil.remindersEnabled {
            _ = await notifications.requestAuthorization()
            await notifications.planifierRappels(objectifML: resultat.totalML, consomméML: consomméAujourdhui())
            await détecterPostSéance()
        }
    }
```

- [ ] **Step 6 : `PreviewSupport` — profil avec sexe**

Dans `Wello/Wello/Views/PreviewSupport.swift`, remplacer la ligne
`ctx.insert(UserProfile(weightKg: 78, medicalFloorML: 2500))` par :

```swift
        let profil = UserProfile(medicalFloorML: 2500)
        profil.sexe = .homme
        ctx.insert(profil)
```

- [ ] **Step 7 : Type-check iOS**

Run la commande de type-check complète (voir en-tête).
Expected: `TYPECHECK_OK` (0 erreur). Aucune référence résiduelle à `weightKg`, `résoudrePoids`,
`dernierPoids`, `poidsDepuisSanté` dans `App/`, `Models/`, `Services/` (les Views suivent en Task 4–5).

> Note : ce type-check compile aussi les Views ; `ProfileView` et `BreakdownCard` référencent encore
> le poids → des erreurs y sont **attendues** ici. Pour valider le périmètre de cette tâche, lancer
> d'abord le type-check **module-seul** des services/modèles :
> ```bash
> rm -rf /tmp/wellomod && mkdir -p /tmp/wellomod
> xcrun --sdk iphonesimulator swiftc -emit-module -module-name WelloKit -target arm64-apple-ios17.0-simulator WelloKit/Sources/WelloKit/*.swift WelloKit/Sources/WelloKit/Models/*.swift -emit-module-path /tmp/wellomod/WelloKit.swiftmodule
> xcrun --sdk iphonesimulator swiftc -typecheck -D DEBUG -enable-upcoming-feature MemberImportVisibility -target arm64-apple-ios17.0-simulator -I /tmp/wellomod Wello/Wello/App/*.swift Wello/Wello/Models/*.swift Wello/Wello/Services/*.swift Wello/Wello/Views/PreviewSupport.swift Wello/Wello/Views/Theme.swift Wello/Wello/Views/MainView.swift Wello/Wello/Views/HistoryView.swift Wello/Wello/Views/AnalyticsView.swift Wello/Wello/Views/DayDetailView.swift Wello/Wello/Views/PaywallView.swift Wello/Wello/Views/WaterGaugeView.swift && echo CORE_OK
> ```
> Expected: `CORE_OK`. (Le type-check complet repasse en Task 5.)

- [ ] **Step 8 : Commit**

```bash
git add Wello/Wello/Models/UserProfile.swift Wello/Wello/Services/ServiceProtocols.swift \
  Wello/Wello/Services/HealthKitService.swift Wello/Wello/Services/Mocks.swift \
  Wello/Wello/Services/HydrationStore.swift Wello/Wello/Views/PreviewSupport.swift
git commit -m "refactor(app): retire le poids du modèle et des services, ajoute le sexe

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4 : UI — Profil (Picker sexe) + BreakdownCard

**Files:**
- Modify: `Wello/Wello/Views/ProfileView.swift`
- Modify: `Wello/Wello/Views/BreakdownCard.swift`

- [ ] **Step 1 : `BreakdownCard` — libellé/icône de la base**

Dans `Wello/Wello/Views/BreakdownCard.swift`, remplacer la ligne :

```swift
                ligne("Base (poids)", breakdown.baseML, icon: "scalemass.fill", teinte: WelloTheme.accent)
```

par :

```swift
                ligne("Base (EFSA)", breakdown.baseML, icon: "person.fill", teinte: WelloTheme.accent)
```

- [ ] **Step 2 : `ProfileView` — remplacer le Stepper poids par un Picker sexe**

Dans `Wello/Wello/Views/ProfileView.swift` :

a) Mettre à jour le commentaire d'en-tête (ligne 5) :

```swift
/// Édition du profil : sexe (base EFSA), plancher médical (validé ≤ 4000), rappels, montants rapides.
```

b) Remplacer la `Section` du poids (le `Stepper` poids, actuellement juste après `if let profil {`) par :

```swift
                    Section {
                        Picker(selection: Binding(get: { profil.sexe ?? .homme },
                                                  set: { profil.sexe = $0; profil.updatedAt = .now
                                                         Task { await store.refreshToday(force: true) } })) {
                            Text("Homme").tag(BiologicalSex.homme)
                            Text("Femme").tag(BiologicalSex.femme)
                        } label: {
                            label("Sexe", profil.sexe?.label, icon: "person.fill", teinte: WelloTheme.accent)
                        }
                    } footer: {
                        Text("Fixe ta base d'hydratation selon les apports de référence EFSA (2000 ml homme / 1600 ml femme).")
                            .font(.system(.caption, design: .rounded))
                    }
```

c) Dans la section « Diagnostic », supprimer la ligne du poids :

```swift
                            diagLigne("Santé (poids)", ok: store.étatServices.poidsDepuisSanté,
                                      détailKO: "poids depuis le profil")
```

(Conserver les lignes « Localisation / météo » et « Notifications ».)

- [ ] **Step 3 : Type-check iOS**

Run la commande de type-check complète.
Expected: `TYPECHECK_OK` (0 erreur). `ProfileView` et `BreakdownCard` ne référencent plus le poids ;
seul `OnboardingView`/`RootView` restent à adapter en Task 5 — ils ne référencent pas le poids et
compilaient déjà, donc le type-check complet doit passer dès maintenant.

- [ ] **Step 4 : Commit**

```bash
git add Wello/Wello/Views/ProfileView.swift Wello/Wello/Views/BreakdownCard.swift
git commit -m "feat(app): Profil Picker sexe + BreakdownCard base EFSA

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5 : Choix forcé du sexe — Onboarding + RootView

**Files:**
- Modify: `Wello/Wello/Views/OnboardingView.swift`
- Modify: `Wello/Wello/Views/RootView.swift`

- [ ] **Step 1 : Réécrire `OnboardingView` avec l'étape de choix du sexe**

Remplacer **tout** le contenu de `Wello/Wello/Views/OnboardingView.swift` par :

```swift
import SwiftUI
import WelloKit

/// Onboarding de premier lancement : écrans d'intro + choix obligatoire du sexe (base EFSA).
struct OnboardingView: View {
    /// Appelé au tap final « Commencer », avec le sexe choisi.
    let onTerminé: (BiologicalSex) -> Void
    @State private var page = 0
    @State private var sexeChoisi: BiologicalSex?
    /// Taille de l'illustration suivant Dynamic Type.
    @ScaledMetric(relativeTo: .largeTitle) private var tailleIcône: CGFloat = 72

    private struct Page { let icon: String; let titre: String; let texte: String }
    private let pages = [
        Page(icon: "drop.fill",
             titre: "Bienvenue dans Wello",
             texte: "Ton suivi d'hydratation personnel, calculé pour toi et 100 % local sur ton iPhone."),
        Page(icon: "figure.run",
             titre: "Un objectif qui s'adapte",
             texte: "Wello ajuste ton objectif du jour selon ton sexe, ton activité (Santé) et la météo — sans jamais descendre sous ton plancher médical."),
        Page(icon: "checkmark.shield.fill",
             titre: "Tes autorisations",
             texte: "Santé, localisation et notifications affinent le calcul et les rappels. Tout refus est géré : l'app reste pleinement utilisable en saisie manuelle."),
    ]

    /// Index de la page de choix du sexe (après les pages d'intro).
    private var pageSexe: Int { pages.count }
    private var estDernièrePage: Bool { page == pageSexe }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { i in
                    pageVue(pages[i]).tag(i)
                }
                sexeVue.tag(pageSexe)
            }
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if !estDernièrePage {
                    withAnimation { page += 1 }
                } else if let sexeChoisi {
                    onTerminé(sexeChoisi)
                }
            } label: {
                Text(estDernièrePage ? "Commencer" : "Suivant")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(WelloTheme.accentGradient,
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .opacity(estDernièrePage && sexeChoisi == nil ? 0.5 : 1)
            }
            .buttonStyle(.plain)
            .disabled(estDernièrePage && sexeChoisi == nil)
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
        .welloBackground()
    }

    private func pageVue(_ p: Page) -> some View {
        VStack(spacing: 22) {
            Image(systemName: p.icon)
                .font(.system(size: tailleIcône, weight: .semibold))
                .foregroundStyle(WelloTheme.accentGradient)
                .accessibilityHidden(true)   // décorative : le titre/texte porte le sens
            Text(p.titre)
                .font(.system(.title, design: .rounded).weight(.bold))
                .foregroundStyle(WelloTheme.ink)
                .multilineTextAlignment(.center)
            Text(p.texte)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(WelloTheme.inkSoft)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
    }

    private var sexeVue: some View {
        VStack(spacing: 22) {
            Image(systemName: "person.fill")
                .font(.system(size: tailleIcône, weight: .semibold))
                .foregroundStyle(WelloTheme.accentGradient)
                .accessibilityHidden(true)
            Text("Ton sexe")
                .font(.system(.title, design: .rounded).weight(.bold))
                .foregroundStyle(WelloTheme.ink)
            Text("Il fixe ta base d'hydratation selon les apports de référence EFSA.")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(WelloTheme.inkSoft)
                .multilineTextAlignment(.center)
            HStack(spacing: 14) {
                choixSexe(.homme, "Homme")
                choixSexe(.femme, "Femme")
            }
        }
        .padding(.horizontal, 32)
    }

    private func choixSexe(_ valeur: BiologicalSex, _ titre: String) -> some View {
        let sélectionné = sexeChoisi == valeur
        return Button {
            sexeChoisi = valeur
        } label: {
            Text(titre)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(sélectionné ? .white : WelloTheme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(sélectionné ? AnyShapeStyle(WelloTheme.accentGradient)
                                        : AnyShapeStyle(WelloTheme.card),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(WelloTheme.accent.opacity(sélectionné ? 0 : 0.35), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(titre)
        .accessibilityAddTraits(sélectionné ? [.isSelected] : [])
    }
}

#if DEBUG
#Preview {
    OnboardingView { _ in }
}
#endif
```

- [ ] **Step 2 : Réécrire `RootView` avec le gating sur `sexe`**

Remplacer **tout** le contenu de `Wello/Wello/Views/RootView.swift` par :

```swift
import SwiftUI
import SwiftData
import WelloKit

/// Racine de l'app : les 3 onglets, avec l'onboarding en plein écran tant que le 1er lancement
/// n'est pas terminé OU que le sexe (base EFSA) n'est pas renseigné.
struct RootView: View {
    @Environment(HydrationStore.self) private var store
    @Query private var profils: [UserProfile]
    @AppStorage("wello.hasOnboarded") private var hasOnboarded = false

    /// Vrai si aucun profil ou profil sans sexe renseigné.
    private var sexeManquant: Bool { (profils.first?.sexe) == nil }

    var body: some View {
        TabView {
            MainView()
                .tabItem { Label("Aujourd'hui", systemImage: "drop.fill") }
            HistoryView()
                .tabItem { Label("Historique", systemImage: "calendar") }
            ProfileView()
                .tabItem { Label("Profil", systemImage: "person.fill") }
        }
        .tint(WelloTheme.accent)
        .fullScreenCover(isPresented: Binding(get: { !hasOnboarded || sexeManquant },
                                              set: { _ in })) {
            OnboardingView { sexe in
                store.profilCourant().sexe = sexe
                hasOnboarded = true
                Task { await store.refreshToday(force: true) }   // déclenche les demandes d'autorisation
            }
        }
    }
}
```

- [ ] **Step 3 : Type-check iOS (complet)**

Run la commande de type-check complète.
Expected: `TYPECHECK_OK` (0 erreur).

- [ ] **Step 4 : Commit**

```bash
git add Wello/Wello/Views/OnboardingView.swift Wello/Wello/Views/RootView.swift
git commit -m "feat(app): choix du sexe obligatoire à l'onboarding (gating EFSA)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6 : Documentation (README + CLAUDE.md)

**Files:**
- Modify: `README.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1 : `README` — bloc « Logique de calcul »**

Dans `README.md`, remplacer le bloc de formule (les lignes ` ```\nbase = poids (kg) × 35 ... ``` `
et le paragraphe juste après qui explique le « poids × 35 ») par :

```
base          = 2000 ml (homme) | 1600 ml (femme)        // apport de boisson EFSA
activité      = min(énergie active kcal × 1, 1000)       // 1 ml/kcal (HealthKit), plafonné
météo         = min(max(0, ressentie°C − 27) × 50, 600)  // ressentie = apparent temp, 0 si indispo
physiologique = base + activité + météo
total         = min(4000, max(plancher médical, physiologique))
```

Et remplacer le paragraphe explicatif du « poids × 35 » par :

```
La base provient des **apports de référence EFSA (2010)** : eau totale 2,5 L/j (homme), 2,0 L/j
(femme), dont ~80 % via les boissons → cible de boisson **2000 ml / 1600 ml**. On ne part pas du
poids (× 35 ml/kg) : ce coefficient estime l'eau *totale* (boissons + aliments + eau métabolique)
et surestime la cible de boisson de ~20-30 %. La personnalisation se fait par sexe + activité
(kcal) + météo, et le **plancher médical** reste prioritaire.
```

- [ ] **Step 2 : `README` — permissions**

Dans `README.md`, section Permissions, remplacer la ligne du `NSHealthShareUsageDescription` par
(retire le poids) :

```
- `NSHealthShareUsageDescription` — lecture des séances et de l'énergie active.
```

(Et, le cas échéant, retirer « du poids » de toute autre mention HealthKit de lecture.)

- [ ] **Step 3 : `CLAUDE.md` — carte du projet**

Dans `CLAUDE.md`, remplacer la parenthèse d'exemples de la ligne `WelloKit/` :

```
- `WelloKit/` — Swift Package, **logique métier pure et testable en CLI** (`HydrationCalculator`,
  `BiologicalSex`, modèles de calcul). Toute logique critique va ici.
```

(Remplace l'exemple `WeightResolver`, supprimé.)

- [ ] **Step 4 : Vérification finale**

```bash
cd WelloKit && swift test && cd ..
```
Expected: tout vert.

Puis la commande de type-check complète → `TYPECHECK_OK`.

- [ ] **Step 5 : Commit**

```bash
git add README.md CLAUDE.md
git commit -m "docs: base EFSA par sexe (formule, permissions, carte projet)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Vérification finale

- [ ] `cd WelloKit && swift test` → vert (HydrationCalculator réécrit, WeightResolver supprimé).
- [ ] Type-check iOS complet → `TYPECHECK_OK`.
- [ ] Previews Xcode (manuel) : onboarding impose le choix Homme/Femme avant « Commencer » ;
  Profil montre le Picker sexe (plus de poids) ; `BreakdownCard` affiche « Base (EFSA) » à 2000/1600 ;
  un profil migré sans sexe redéclenche l'onboarding au lancement.

## Étapes Xcode / appareil (manuelles, hors CLI)

- Ajouter `BiologicalSex.swift` (package `WelloKit`, automatique) ; aucun nouveau fichier app.
- **Info.plist** : ajuster `NSHealthShareUsageDescription` pour retirer la mention du poids.
- Premier lancement après migration : le profil existant a `sexe == nil` → l'app redemande le sexe.

---

## Self-Review (effectuée)

**Couverture de la spec :**
- Base EFSA par sexe (2000/1600) + constantes → Task 1 ✅
- `BiologicalSex` enum + `CalculatorInputs.sex` → Task 1 ✅
- Suppression WeightResolver → Task 2 ✅ ; suppression poids modèle/HealthKit/diagnostic → Task 3 ✅
- `sexe` optionnel + gating calcul (`breakdown=nil`) → Task 3 ✅ ; gating onboarding → Task 5 ✅
- Choix forcé onboarding (étape + bouton désactivé + closure `onTerminé(BiologicalSex)`) → Task 5 ✅
- UI Profil (Picker) + BreakdownCard → Task 4 ✅
- Migration légère (sexeRaw optionnel, weightKg retiré) → Task 3 ✅
- Historique non recalculé : aucun code ne touche les `DailyGoal` passés (upsert du jour seul) ✅
- Docs README + CLAUDE.md → Task 6 ✅

**Placeholders :** aucun — chaque étape contient le code/texte réel.

**Cohérence des types :** `BiologicalSex` (`.homme`/`.femme`, `.label`, `init(rawValue:)`),
`CalculatorInputs(sex:activeEnergyKcal:weather:medicalFloorML:)`, `UserProfile.sexe`,
`HealthKitServicing` sans `dernierPoids`, `ÉtatServices` sans `poidsDepuisSanté`,
`OnboardingView.onTerminé: (BiologicalSex) -> Void` — définis en Tasks 1/3/5 et utilisés à
l'identique dans le store, les vues et RootView.
