# Wello — App iOS de suivi d'hydratation — Design (Phase 1 : cœur iOS)

**Date :** 2026-06-03
**Statut :** Validé pour implémentation (Phase 1)

## Contexte & objectif

Application iOS personnelle, mono-utilisateur, qui calcule un objectif d'hydratation
quotidien personnalisé et aide à le suivre. Calcul basé sur le poids, l'activité physique
(HealthKit), la météo locale (Open-Meteo) et un plancher médical fixe (suivi de calculs
rénaux calciques). 100 % local, pas de backend, pas de compte, pas de sync multi-device.

**Phase 1 (ce doc) :** cœur iOS — app complète 3 écrans, `HydrationCalculator` testé,
SwiftData, HealthKit, météo, notifications.
**Phase 2 (hors de ce doc) :** watchOS, Widget iOS, complication Watch. Le découpage
services/calculateur est conçu pour les accueillir sans refonte.

## Stack

- SwiftUI (iOS 17+)
- SwiftData (persistance locale)
- HealthKit (lecture workouts/poids, écriture hydratation)
- Open-Meteo (API gratuite sans clé) pour la météo, en best-effort
- CoreLocation (coordonnées pour la météo, best-effort)
- UNUserNotificationCenter (rappels)
- Swift 6 strict concurrency
- Commentaires en français, code idiomatique SwiftUI/SwiftData

## Décisions d'architecture validées

- **Pattern « MV » moderne** (pas de ViewModels). Les vues utilisent `@Query` SwiftData
  directement ; les effets de bord passent par des services `@Observable` injectés via
  `.environment()`. `HydrationCalculator` reste une struct pure sans dépendance Apple.
- **Scaffolding :** l'utilisateur crée le projet et les targets dans Xcode (Xcode 26.5,
  Swift 6.3.2). On fournit une arborescence de sources à glisser + un Swift Package local
  `WelloKit` pour la logique pure (compilable et testable en CLI, sans Xcode/HealthKit).
- **Services derrière des protocoles** pour rester mockables (previews/tests).

## Structure des livrables

```
Wello/
├─ WelloKit/                      ← Swift Package (compilable + testable en CLI)
│  ├─ Package.swift
│  ├─ Sources/WelloKit/
│  │  ├─ HydrationCalculator.swift   (struct pure, Foundation seul)
│  │  └─ Models/ (CalculatorInputs, GoalBreakdown, WeatherSnapshot…)
│  └─ Tests/WelloKitTests/HydrationCalculatorTests.swift
├─ Wello/                         ← sources app iOS (à ajouter au target app)
│  ├─ App/        (WelloApp, ModelContainer, injection environnement)
│  ├─ Models/     (UserProfile, DailyGoal, HydrationLog — @Model SwiftData)
│  ├─ Services/   (protocoles + impls : HealthKit, Weather, Location, Notifications, HydrationStore)
│  └─ Views/      (Main, Profile, History + composants jauge/breakdown)
└─ README.md
```

`WelloKit` est ajouté comme **local Swift Package** dans le projet Xcode et lié au target app.

## Logique métier — `HydrationCalculator` (pur, WelloKit)

Constantes nommées :
`mlParKg = 35`, `mlParMinEffort = 11`, `plafondActivité = 1000`,
`bonusTemp = 300` (température moyenne > 28 °C), `bonusHumidité = 200` (humidité > 70 %),
`plafondGlobal = 4000`.

```
base          = weightKg × 35
activité      = min(minutesEffort × 11, 1000)
météo         = (temp > 28 ? 300 : 0) + (humidité > 70 ? 200 : 0)   // 0 si snapshot absent (nil)
physiologique = base + activité + météo
total         = min(4000, max(plancherMédical, physiologique))
```

`calculate(inputs:) -> GoalBreakdown` renvoie chaque poste **et** deux drapeaux UI :
- `plancherContraignant` : le plancher médical a déterminé le total.
- `plafondAppliqué` : total bridé à 4000 (sécurité anti-hyperhydratation).

**Cas limite documenté :** un plancher médical > 4000 ml est considéré invalide (le Profil
valide `medicalFloorML ≤ 4000`). Si malgré tout `plancher > plafond`, le plafond de sécurité
prime (jamais d'affichage > 4000).

`CalculatorInputs` : `weightKg: Double`, `effortMinutes: Int`, `weather: WeatherSnapshot?`,
`medicalFloorML: Int`. `WeatherSnapshot` : `temperatureC: Double`, `humidityPct: Double`.
`WelloKit` est pur et `Sendable`.

## Modèle de données (SwiftData)

- `UserProfile` : `weightKg: Double`, `medicalFloorML: Int` (ex. 2500),
  `remindersEnabled: Bool`, `updatedAt: Date`.
- `DailyGoal` : `date: Date`, `baseML: Int`, `activityBonusML: Int`, `weatherBonusML: Int`,
  `medicalFloorML: Int`, `totalML: Int`, `calculatedAt: Date`.
- `HydrationLog` : `amountML: Int`, `loggedAt: Date`, `source: String` (`"app"` | `"healthkit"`).

Mono-utilisateur : on récupère le premier `UserProfile` ou on en crée un par défaut au lancement.

**Source de vérité du « consommé » = somme des `HydrationLog` du jour.** On ne relit pas
HealthKit pour compter (l'écriture `dietaryWater` sert uniquement à l'intégration Santé.app),
ce qui évite tout double comptage en Phase 1.

## Services (protocoles → impls + mocks)

- `HealthKitServicing` : `requestAuthorization()`, `minutesEffortDuJour() -> Int`,
  `dernierPoids() -> Double?`, `écrireEau(ml:date:)`. Impl réelle + mock pour previews.
- `WeatherServicing` : `météoDuJour(lat:lon:) -> WeatherSnapshot?` via Open-Meteo, best-effort,
  `nil` si échec réseau/API.
- `LocationServicing` : CoreLocation one-shot → coordonnées (alimente la météo), best-effort.
- `NotificationServicing` : rappels fenêtre 7h–21h, espacement minimum (jamais deux rapprochés),
  rappel post-séance (+500 ml dans l'heure, détecté via workout), rappel retard à 14h & 17h,
  action directe « logger 250 ml » sans ouvrir l'app, snooze / désactiver pour la journée.
- `HydrationStore` (`@Observable`, injecté via environnement) : orchestration.
  - `refreshToday()` : poids (HealthKit, fallback `UserProfile.weightKg`) + effort (HealthKit)
    + météo (best-effort) → `HydrationCalculator.calculate` → upsert du `DailyGoal` du jour.
  - `log(ml:)` : crée `HydrationLog(source:"app")` + `écrireEau` HealthKit + recalcule le consommé.

## Flux de données

1. **Lancement** → garantir `UserProfile` → `refreshToday()`.
2. **`refreshToday()`** → lecture effort (HealthKit) + poids (HealthKit sinon profil) +
   météo (best-effort) → calcul → upsert `DailyGoal` du jour.
3. **Log rapide** → `HydrationLog(source:"app")` + écriture `dietaryWater` HealthKit → recompute.
4. **Consommé** = somme des `HydrationLog` du jour.

## Écrans iOS

- **Principal :** jauge circulaire (consommé / objectif), boutons de log rapide 150 / 250 / 500 ml,
  carte breakdown (base + activité + météo + plancher), badges si plancher contraignant / plafond
  appliqué.
- **Profil :** édition `weightKg`, `medicalFloorML` (validé ≤ 4000), toggle rappels.
- **Historique :** liste des jours, objectif vs consommé.

## Permissions & dégradation gracieuse

- HealthKit : lecture workouts + `bodyMass`, écriture `dietaryWater`.
- Localisation : when-in-use (pour la météo).
- Notifications : rappels.

**Refus géré partout** — l'app reste pleinement utilisable en saisie manuelle :
- Météo/localisation indisponible → bonus météo = 0, le calcul tourne.
- HealthKit refusé → effort = 0, poids depuis le profil, log manuel uniquement, pas d'écriture HK.
- Notifications refusées → pas de rappels, le toggle reflète l'état réel.

Clés Info.plist à ajouter côté target (documentées dans le README) :
`NSHealthShareUsageDescription`, `NSHealthUpdateUsageDescription`,
`NSLocationWhenInUseUsageDescription` + activation de la capability HealthKit.

## Tests (CLI, vérifiables via `swift test` sur WelloKit)

`HydrationCalculatorTests` couvre :
- plancher médical contraignant (physiologique < plancher),
- plafond global (physiologique > 4000 → bridé),
- météo absente (`weather == nil` → bonus 0, calcul OK),
- activité plafonnée (`min(... , 1000)`),
- bonus météo combinés (temp seule / humidité seule / les deux),
- fallback poids (poids absent côté HealthKit → `UserProfile.weightKg`),
- cohérence du « consommé » (pas de double comptage).

## Concurrence

Swift 6 strict concurrency : `WelloKit` pur et `Sendable` ; services en `async/await`,
`@MainActor` là où requis pour SwiftData/UI.

## Hors périmètre (Phase 1 et global)

- Phase 1 : watchOS, Widget iOS, complication (→ Phase 2).
- Global : pas de backend, pas de compte, pas de sync multi-device, pas de correction
  alimentation (retirée volontairement, trop imprécise).

## Livrables

- Arborescence de sources structurée + `WelloKit` (Swift Package compilable/testable).
- README : lancement, permissions HealthKit/Localisation/Notifications, et où ajuster le
  plancher médical.
