# Rappels adaptatifs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Livrer la feature premium « Rappels adaptatifs » : apprendre les trous d'hydratation récurrents de l'utilisateur et planifier des rappels préventifs, 100 % local.

**Architecture:** Logique pure et testable dans `WelloKit` (`AdaptiveReminderPlanner` : détection des trous + dérivation de la fenêtre d'éveil). La couche iOS orchestre : `HydrationStore` récupère l'historique SwiftData, lit le sommeil HealthKit (best-effort), appelle le planner, et passe les heures à `NotificationService`. Gating `free`/`plus` via `Entitlements`.

**Tech Stack:** Swift 6, Swift Testing (`import Testing`), SwiftUI/SwiftData, HealthKit (`sleepAnalysis`), UserNotifications.

**Référence spec :** `docs/superpowers/specs/2026-06-08-rappels-adaptatifs-design.md`

---

## Carte des fichiers

| Fichier | Rôle | Action |
|---|---|---|
| `WelloKit/Sources/WelloKit/AdaptiveReminders.swift` | Types purs + planner (détection trous, fenêtre d'éveil, cold-start) | **Créer** |
| `WelloKit/Tests/WelloKitTests/AdaptiveRemindersTests.swift` | Tests `swift test` du planner | **Créer** |
| `Wello/Wello/Services/ServiceProtocols.swift` | + `périodesSommeil`, + `planifierRappelsAdaptatifs` aux protocoles | Modifier |
| `Wello/Wello/Services/HealthKitService.swift` | Lecture réelle `sleepAnalysis` | Modifier |
| `Wello/Wello/Services/NotificationService.swift` | Planification des rappels adaptatifs + purge croisée | Modifier |
| `Wello/Wello/Services/Mocks.swift` | Mocks pour les nouvelles méthodes | Modifier |
| `Wello/Wello/Services/HydrationStore.swift` | Orchestration : palier, historique, fenêtre, état UI | Modifier |
| `Wello/Wello/App/WelloApp.swift` | Câblage du closure d'entitlement | Modifier |
| `Wello/Wello/Views/ProfileView.swift` | Sous-titre d'état + teaser premium | Modifier |
| `Wello/Wello/Views/PreviewSupport.swift` | Factory store avec param premium | Modifier |

**Note :** aucun nouveau fichier dans le target app (que des modifications) ; le seul nouveau source est dans `WelloKit`, couvert par les globs de la commande de vérification du `CLAUDE.md`. **Pas de modif de cette commande.**

---

## Task 1 : WelloKit — types, constantes, cold-start

**Files:**
- Create: `WelloKit/Sources/WelloKit/AdaptiveReminders.swift`
- Test: `WelloKit/Tests/WelloKitTests/AdaptiveRemindersTests.swift`

- [ ] **Step 1 : Écrire le test d'échec (cold-start)**

Create `WelloKit/Tests/WelloKitTests/AdaptiveRemindersTests.swift` :

```swift
import Testing
import Foundation
@testable import WelloKit

@Suite("AdaptiveReminders")
struct AdaptiveRemindersTests {
    let planner = AdaptiveReminderPlanner()

    @Test("cold-start : moins de 7 jours de données → données insuffisantes")
    func coldStart() {
        let six = (0..<6).map { _ in JourDePrises(minutesDePrise: [480, 720]) }
        #expect(planner.aAssezDeDonnées(six) == false)
        let sept = (0..<7).map { _ in JourDePrises(minutesDePrise: [480, 720]) }
        #expect(planner.aAssezDeDonnées(sept) == true)
    }

    @Test("cold-start : un jour sans prise ne compte pas")
    func coldStartJoursVides() {
        var jours = (0..<7).map { _ in JourDePrises(minutesDePrise: [480]) }
        jours.append(JourDePrises(minutesDePrise: []))
        #expect(planner.aAssezDeDonnées(jours) == true)         // 7 jours pleins
        let presqueVide = (0..<6).map { _ in JourDePrises(minutesDePrise: [480]) }
            + [JourDePrises(minutesDePrise: [])]
        #expect(planner.aAssezDeDonnées(presqueVide) == false)  // 6 pleins seulement
    }
}
```

- [ ] **Step 2 : Lancer le test, vérifier l'échec de compilation**

Run: `cd WelloKit && swift test --filter AdaptiveReminders`
Expected: FAIL — `cannot find 'AdaptiveReminderPlanner' in scope`.

- [ ] **Step 3 : Créer le fichier source minimal**

Create `WelloKit/Sources/WelloKit/AdaptiveReminders.swift` :

```swift
import Foundation

/// Fenêtre d'éveil quotidienne, en minutes depuis minuit.
public struct FenêtreÉveil: Sendable, Equatable {
    public let réveilMin: Int
    public let coucherMin: Int
    public init(réveilMin: Int, coucherMin: Int) {
        self.réveilMin = réveilMin
        self.coucherMin = coucherMin
    }
    /// Repli ultime quand ni le sommeil ni l'historique ne renseignent la fenêtre.
    public static let défaut = FenêtreÉveil(réveilMin: 7 * 60, coucherMin: 21 * 60)
}

/// Un intervalle de sommeil (source HealthKit, mappé en type pur pour la dérivation testable).
public struct PériodeSommeil: Sendable {
    public let début: Date
    public let fin: Date
    public init(début: Date, fin: Date) {
        self.début = début
        self.fin = fin
    }
}

/// Les prises d'un jour, en minutes depuis minuit (ordre indifférent ; trié à l'usage).
public struct JourDePrises: Sendable {
    public let minutesDePrise: [Int]
    public init(minutesDePrise: [Int]) {
        self.minutesDePrise = minutesDePrise
    }
}

/// Planificateur pur des rappels adaptatifs : apprend les trous d'hydratation récurrents
/// et en déduit des heures de rappel préventives. Aucune dépendance UIKit/HealthKit →
/// entièrement testable via `swift test`.
public struct AdaptiveReminderPlanner: Sendable {
    // Constantes de réglage (documentées, ajustables sans toucher la logique).
    /// Fenêtre d'apprentissage glissante.
    public static let joursHistoire = 14
    /// Données minimales avant d'activer l'adaptatif (sinon rappels fixes).
    public static let minJoursPourAdaptatif = 7
    /// Durée minimale d'un « trou » d'hydratation (minutes).
    static let minGapMin = 120
    /// Fraction des jours où un créneau doit apparaître pour être « habituel ».
    static let seuilRécurrence = 0.40
    /// Anticipation : on rappelle ce nombre de minutes avant d'atteindre le seuil de trou.
    static let leadTimeMin = 15
    /// Espacement minimal entre deux rappels d'une même journée (minutes).
    static let espacementMin = 90
    /// Nombre maximal de rappels adaptatifs par jour.
    public static let plafondParJour = 6

    public init() {}

    /// Vrai si l'historique contient assez de jours non vides pour apprendre.
    public func aAssezDeDonnées(_ historique: [JourDePrises]) -> Bool {
        historique.filter { !$0.minutesDePrise.isEmpty }.count >= Self.minJoursPourAdaptatif
    }
}
```

- [ ] **Step 4 : Lancer le test, vérifier le succès**

Run: `cd WelloKit && swift test --filter AdaptiveReminders`
Expected: PASS (2 tests).

- [ ] **Step 5 : Commit**

```bash
git add WelloKit/Sources/WelloKit/AdaptiveReminders.swift WelloKit/Tests/WelloKitTests/AdaptiveRemindersTests.swift
git commit -m "feat(kit): types + cold-start des rappels adaptatifs"
```

---

## Task 2 : WelloKit — dérivation de la fenêtre depuis l'historique

**Files:**
- Modify: `WelloKit/Sources/WelloKit/AdaptiveReminders.swift`
- Test: `WelloKit/Tests/WelloKitTests/AdaptiveRemindersTests.swift`

- [ ] **Step 1 : Écrire les tests d'échec**

Ajouter dans `AdaptiveRemindersTests.swift`, dans le `struct` :

```swift
    @Test("fenêtre historique : percentiles des 1ʳᵉˢ/dernières prises")
    func fenêtreHistorique() {
        let jours = (0..<10).map { _ in JourDePrises(minutesDePrise: [480, 720, 1200]) }
        let f = planner.fenêtreDepuisHistorique(jours)
        #expect(f == FenêtreÉveil(réveilMin: 480, coucherMin: 1200))
    }

    @Test("fenêtre historique : aucune donnée → nil")
    func fenêtreHistoriqueVide() {
        #expect(planner.fenêtreDepuisHistorique([]) == nil)
        #expect(planner.fenêtreDepuisHistorique([JourDePrises(minutesDePrise: [])]) == nil)
    }

    @Test("fenêtre historique : bornes clampées")
    func fenêtreHistoriqueClamp() {
        // Réveil très tôt (2:00) et coucher très tard (23:50) → clampés.
        let jours = (0..<8).map { _ in JourDePrises(minutesDePrise: [120, 1430]) }
        let f = planner.fenêtreDepuisHistorique(jours)
        #expect(f?.réveilMin == 240)    // plancher 4:00
        #expect(f?.coucherMin == 1410)  // plafond 23:30
    }
```

- [ ] **Step 2 : Vérifier l'échec**

Run: `cd WelloKit && swift test --filter AdaptiveReminders`
Expected: FAIL — `value of type 'AdaptiveReminderPlanner' has no member 'fenêtreDepuisHistorique'`.

- [ ] **Step 3 : Implémenter la dérivation + helpers**

Ajouter dans `AdaptiveReminders.swift`, dans le `struct AdaptiveReminderPlanner` :

```swift
    /// Fenêtre d'éveil déduite des habitudes de prises : réveil ≈ 15ᵉ percentile des 1ʳᵉˢ
    /// prises, coucher ≈ 85ᵉ percentile des dernières. `nil` si aucune donnée exploitable.
    public func fenêtreDepuisHistorique(_ historique: [JourDePrises]) -> FenêtreÉveil? {
        var premières: [Int] = []
        var dernières: [Int] = []
        for jour in historique {
            let triées = jour.minutesDePrise.sorted()
            guard let p = triées.first, let d = triées.last else { continue }
            premières.append(p)
            dernières.append(d)
        }
        guard !premières.isEmpty else { return nil }
        let réveil = Self.clampRéveil(percentile(premières, 15))
        let coucher = Self.clampCoucher(percentile(dernières, 85))
        return FenêtreÉveil(réveilMin: réveil, coucherMin: coucher)
    }

    // Bornes de sécurité pour ne jamais rappeler en pleine nuit.
    static func clampRéveil(_ m: Int) -> Int { min(max(m, 240), 660) }    // 4:00–11:00
    static func clampCoucher(_ m: Int) -> Int { min(max(m, 1080), 1410) } // 18:00–23:30
```

Et, **en dehors** du `struct` (fonctions libres internes au module), à la fin du fichier :

```swift
/// Percentile par rang le plus proche (p ∈ 0...100), sur une liste non vide.
func percentile(_ valeurs: [Int], _ p: Int) -> Int {
    let triées = valeurs.sorted()
    guard triées.count > 1 else { return triées.first ?? 0 }
    let rang = Int((Double(p) / 100.0 * Double(triées.count - 1)).rounded())
    return triées[min(max(rang, 0), triées.count - 1)]
}

/// Médiane entière d'une liste non vide (moyenne basse des deux centraux si pair).
func médiane(_ valeurs: [Int]) -> Int {
    let triées = valeurs.sorted()
    let n = triées.count
    guard n > 0 else { return 0 }
    if n % 2 == 1 { return triées[n / 2] }
    return (triées[n / 2 - 1] + triées[n / 2]) / 2
}
```

- [ ] **Step 4 : Vérifier le succès**

Run: `cd WelloKit && swift test --filter AdaptiveReminders`
Expected: PASS.

- [ ] **Step 5 : Commit**

```bash
git add WelloKit/Sources/WelloKit/AdaptiveReminders.swift WelloKit/Tests/WelloKitTests/AdaptiveRemindersTests.swift
git commit -m "feat(kit): fenêtre d'éveil depuis l'historique de prises"
```

---

## Task 3 : WelloKit — dérivation de la fenêtre depuis le sommeil

**Files:**
- Modify: `WelloKit/Sources/WelloKit/AdaptiveReminders.swift`
- Test: `WelloKit/Tests/WelloKitTests/AdaptiveRemindersTests.swift`

- [ ] **Step 1 : Écrire les tests d'échec**

Ajouter dans `AdaptiveRemindersTests.swift` :

```swift
    @Test("fenêtre sommeil : réveil = fin de sommeil, coucher = début")
    func fenêtreSommeil() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Paris")!
        func date(_ jour: Int, _ h: Int, _ m: Int) -> Date {
            cal.date(from: DateComponents(year: 2026, month: 6, day: jour, hour: h, minute: m))!
        }
        // 3 nuits : endormi 23:00 → réveil 07:00.
        let périodes = (1...3).map { j in
            PériodeSommeil(début: date(j, 23, 0), fin: date(j + 1, 7, 0))
        }
        let f = planner.fenêtreDepuisSommeil(périodes, calendar: cal)
        #expect(f == FenêtreÉveil(réveilMin: 420, coucherMin: 1380))
    }

    @Test("fenêtre sommeil : aucune période → nil")
    func fenêtreSommeilVide() {
        #expect(planner.fenêtreDepuisSommeil([], calendar: .current) == nil)
    }
```

- [ ] **Step 2 : Vérifier l'échec**

Run: `cd WelloKit && swift test --filter AdaptiveReminders`
Expected: FAIL — `has no member 'fenêtreDepuisSommeil'`.

- [ ] **Step 3 : Implémenter**

Ajouter dans `struct AdaptiveReminderPlanner` :

```swift
    /// Fenêtre d'éveil déduite du sommeil : réveil = médiane des fins de sommeil (matin),
    /// coucher = médiane des débuts de sommeil (soir). `nil` si aucune période.
    public func fenêtreDepuisSommeil(_ périodes: [PériodeSommeil],
                                     calendar: Calendar = .current) -> FenêtreÉveil? {
        guard !périodes.isEmpty else { return nil }
        let fins = périodes.map { Self.minuteDuJour($0.fin, calendar) }
        let débuts = périodes.map { Self.minuteDuJour($0.début, calendar) }
        return FenêtreÉveil(réveilMin: Self.clampRéveil(médiane(fins)),
                            coucherMin: Self.clampCoucher(médiane(débuts)))
    }

    /// Minutes depuis minuit d'une date dans le calendrier donné.
    static func minuteDuJour(_ date: Date, _ calendar: Calendar) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
```

- [ ] **Step 4 : Vérifier le succès**

Run: `cd WelloKit && swift test --filter AdaptiveReminders`
Expected: PASS.

- [ ] **Step 5 : Commit**

```bash
git add WelloKit/Sources/WelloKit/AdaptiveReminders.swift WelloKit/Tests/WelloKitTests/AdaptiveRemindersTests.swift
git commit -m "feat(kit): fenêtre d'éveil depuis le sommeil HealthKit"
```

---

## Task 4 : WelloKit — détection des trous & plan de rappels

**Files:**
- Modify: `WelloKit/Sources/WelloKit/AdaptiveReminders.swift`
- Test: `WelloKit/Tests/WelloKitTests/AdaptiveRemindersTests.swift`

- [ ] **Step 1 : Écrire les tests d'échec**

Ajouter dans `AdaptiveRemindersTests.swift` un helper de date et les tests :

```swift
    // Calendrier + fabrique de Date pour les tests de plan.
    private func calTest() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        return c
    }
    private func aujourdhui(_ cal: Calendar, _ h: Int, _ m: Int) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: h, minute: m))!
    }
    /// Minutes depuis minuit d'une Date produite par le plan (pour les assertions).
    private func minute(_ cal: Calendar, _ d: Date) -> Int {
        AdaptiveReminderPlanner.minuteDuJour(d, cal)
    }

    @Test("plan : trou récurrent l'après-midi → rappels préventifs")
    func planDétection() {
        let cal = calTest()
        let jours = (0..<10).map { _ in
            JourDePrises(minutesDePrise: [480, 630, 780, 930, 1080, 1230])
        }
        let plan = planner.planRappels(historique: jours, fenêtre: .défaut,
                                       now: aujourdhui(cal, 7, 0), objectifAtteint: false,
                                       calendar: cal)
        // Trous démarrant à 480/630/780/930/1080 → rappels = start + 120 − 15.
        #expect(plan.map { minute(cal, $0) } == [585, 735, 885, 1035, 1185])
    }

    @Test("plan : créneau non récurrent ignoré")
    func planNonRécurrent() {
        let cal = calTest()
        // 2 jours sur 10 ont un trou ; sous le seuil 40 % → aucun rappel.
        var jours = (0..<8).map { _ in JourDePrises(minutesDePrise: [480, 600, 720, 840, 960, 1080, 1200]) }
        jours += (0..<2).map { _ in JourDePrises(minutesDePrise: [480]) }
        let plan = planner.planRappels(historique: jours, fenêtre: .défaut,
                                       now: aujourdhui(cal, 7, 0), objectifAtteint: false,
                                       calendar: cal)
        #expect(plan.isEmpty)
    }

    @Test("plan : objectif atteint → aucun rappel")
    func planObjectifAtteint() {
        let cal = calTest()
        let jours = (0..<10).map { _ in JourDePrises(minutesDePrise: [480, 1230]) }
        let plan = planner.planRappels(historique: jours, fenêtre: .défaut,
                                       now: aujourdhui(cal, 7, 0), objectifAtteint: true,
                                       calendar: cal)
        #expect(plan.isEmpty)
    }

    @Test("plan : espacement < 90 min → le 2ᵉ créneau saute")
    func planEspacement() {
        let cal = calTest()
        // 5 jours : trou démarrant à 480 → rappel 585 (h9).
        // 5 jours : trou démarrant à 510 → rappel 615 (h10). 615−585 = 30 < 90.
        let a = (0..<5).map { _ in JourDePrises(minutesDePrise: [480]) }
        let b = (0..<5).map { _ in JourDePrises(minutesDePrise: [510]) }
        let plan = planner.planRappels(historique: a + b, fenêtre: .défaut,
                                       now: aujourdhui(cal, 7, 0), objectifAtteint: false,
                                       calendar: cal)
        #expect(plan.map { minute(cal, $0) } == [585])
    }

    @Test("plan : plafonné à 6 rappels/jour")
    func planPlafond() {
        let cal = calTest()
        let fenêtre = FenêtreÉveil(réveilMin: 300, coucherMin: 1320)
        let jours = (0..<10).map { _ in
            JourDePrises(minutesDePrise: [430, 560, 690, 820, 950, 1080, 1210])
        }
        let plan = planner.planRappels(historique: jours, fenêtre: fenêtre,
                                       now: aujourdhui(cal, 5, 0), objectifAtteint: false,
                                       calendar: cal)
        #expect(plan.count == 6)
    }

    @Test("plan : seuls les rappels futurs sont retournés")
    func planFutur() {
        let cal = calTest()
        let jours = (0..<10).map { _ in
            JourDePrises(minutesDePrise: [480, 630, 780, 930, 1080, 1230])
        }
        // now = 17:30 (1050) → seul 1185 (19:45) est futur.
        let plan = planner.planRappels(historique: jours, fenêtre: .défaut,
                                       now: aujourdhui(cal, 17, 30), objectifAtteint: false,
                                       calendar: cal)
        #expect(plan.map { minute(cal, $0) } == [1185])
    }
```

- [ ] **Step 2 : Vérifier l'échec**

Run: `cd WelloKit && swift test --filter AdaptiveReminders`
Expected: FAIL — `has no member 'planRappels'`.

- [ ] **Step 3 : Implémenter le plan**

Ajouter dans `struct AdaptiveReminderPlanner` :

```swift
    /// Heures de rappel pour aujourd'hui, déduites des trous d'hydratation récurrents.
    /// Préventif : chaque rappel vise `leadTime` avant que l'utilisateur n'atteigne sa durée
    /// de trou habituelle. Vide si l'objectif du jour est déjà atteint.
    public func planRappels(historique: [JourDePrises], fenêtre: FenêtreÉveil,
                            now: Date, objectifAtteint: Bool,
                            calendar: Calendar = .current) -> [Date] {
        guard !objectifAtteint else { return [] }
        let nbJours = historique.count
        guard nbJours > 0 else { return [] }

        // 1. Minutes de rappel candidates par jour (à partir des trous > minGap).
        var minutesParHeure: [Int: [Int]] = [:]
        var joursParHeure: [Int: Int] = [:]
        for jour in historique {
            let prises = jour.minutesDePrise
                .filter { $0 >= fenêtre.réveilMin && $0 <= fenêtre.coucherMin }
                .sorted()
            let bornes = [fenêtre.réveilMin] + prises + [fenêtre.coucherMin]
            var candidats: [Int] = []
            for i in 0..<(bornes.count - 1) where bornes[i + 1] - bornes[i] > Self.minGapMin {
                let rappel = bornes[i] + Self.minGapMin - Self.leadTimeMin
                if rappel > fenêtre.réveilMin && rappel < fenêtre.coucherMin {
                    candidats.append(rappel)
                }
            }
            for h in Set(candidats.map { $0 / 60 }) { joursParHeure[h, default: 0] += 1 }
            for m in candidats { minutesParHeure[m / 60, default: []].append(m) }
        }

        // 2. Créneaux horaires « habituels » (présents sur ≥ seuilRécurrence des jours).
        let seuilJours = max(1, Int((Double(nbJours) * Self.seuilRécurrence).rounded(.up)))
        var minutesRetenues: [Int] = []
        for (h, jours) in joursParHeure where jours >= seuilJours {
            if let mins = minutesParHeure[h], !mins.isEmpty {
                minutesRetenues.append(médiane(mins))
            }
        }
        minutesRetenues.sort()

        // 3. Espacement ≥ espacementMin sur la journée entière, puis plafond.
        var planJournée: [Int] = []
        for m in minutesRetenues {
            if let dernier = planJournée.last, m - dernier < Self.espacementMin { continue }
            planJournée.append(m)
            if planJournée.count >= Self.plafondParJour { break }
        }

        // 4. Conversion en Date d'aujourd'hui, filtré aux heures strictement futures.
        let débutJour = calendar.startOfDay(for: now)
        return planJournée.compactMap { m in
            guard let d = calendar.date(byAdding: .minute, value: m, to: débutJour), d > now else { return nil }
            return d
        }
    }
```

- [ ] **Step 4 : Vérifier le succès (toute la suite)**

Run: `cd WelloKit && swift test --filter AdaptiveReminders`
Expected: PASS (tous les tests de Tasks 1–4).

- [ ] **Step 5 : Lancer la suite complète WelloKit (non-régression)**

Run: `cd WelloKit && swift test`
Expected: PASS (toutes suites).

- [ ] **Step 6 : Commit**

```bash
git add WelloKit/Sources/WelloKit/AdaptiveReminders.swift WelloKit/Tests/WelloKitTests/AdaptiveRemindersTests.swift
git commit -m "feat(kit): détection des trous habituels + plan de rappels préventifs"
```

---

## Task 5 : App — lecture du sommeil HealthKit

**Files:**
- Modify: `Wello/Wello/Services/ServiceProtocols.swift:24` (dans `HealthKitServicing`)
- Modify: `Wello/Wello/Services/HealthKitService.swift`
- Modify: `Wello/Wello/Services/Mocks.swift:5-13` (`MockHealthKitService`)

- [ ] **Step 1 : Ajouter la méthode au protocole**

Dans `ServiceProtocols.swift`, à la fin du `protocol HealthKitServicing` (après `dernierWorkoutTerminé`, ligne ~26) :

```swift
    /// Périodes de sommeil (asleep) depuis `date`, pour déduire la fenêtre d'éveil.
    /// Vide si refusé/indisponible.
    func périodesSommeil(depuis date: Date) async -> [PériodeSommeil]
```

- [ ] **Step 2 : Implémenter dans le service réel**

Dans `HealthKitService.swift` : ajouter `import WelloKit` en tête (sous `import HealthKit`), puis déclarer le type sommeil près des autres (ligne ~14) :

```swift
    private let sleepType = HKCategoryType(.sleepAnalysis)
```

Ajouter `sleepType` au set de lecture dans `requestAuthorization` :

```swift
        let read: Set<HKObjectType> = [workoutType, waterType, energyType, sleepType]
```

Puis ajouter la méthode (après `dernierWorkoutTerminé`) :

```swift
    func périodesSommeil(depuis date: Date) async -> [PériodeSommeil] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        let prédicat = HKQuery.predicateForSamples(withStart: date, end: .now)
        let samples: [HKCategorySample] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: sleepType, predicate: prédicat,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                cont.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            store.execute(q)
        }
        let asleep: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue
        ]
        return samples
            .filter { asleep.contains($0.value) }
            .map { PériodeSommeil(début: $0.startDate, fin: $0.endDate) }
    }
```

- [ ] **Step 3 : Ajouter au mock**

Dans `Mocks.swift`, dans `struct MockHealthKitService`, ajouter une propriété et la méthode :

```swift
    var périodesSommeilMock: [PériodeSommeil] = []
    func périodesSommeil(depuis date: Date) async -> [PériodeSommeil] { périodesSommeilMock }
```

- [ ] **Step 4 : Type-check iOS hors Xcode**

Run (depuis la racine) :

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
  Wello/Wello/Services/*.swift Wello/Wello/Views/*.swift && echo "OK 0 erreur"
```

Expected: `OK 0 erreur`.

- [ ] **Step 5 : Commit**

```bash
git add Wello/Wello/Services/ServiceProtocols.swift Wello/Wello/Services/HealthKitService.swift Wello/Wello/Services/Mocks.swift
git commit -m "feat(premium): lecture des périodes de sommeil HealthKit"
```

---

## Task 6 : App — planification des rappels adaptatifs

**Files:**
- Modify: `Wello/Wello/Services/ServiceProtocols.swift` (dans `NotificationServicing`)
- Modify: `Wello/Wello/Services/NotificationService.swift`
- Modify: `Wello/Wello/Services/Mocks.swift:25-33` (`MockNotificationService`)

- [ ] **Step 1 : Ajouter la méthode au protocole**

Dans `ServiceProtocols.swift`, dans `protocol NotificationServicing`, après `planifierRappels(...)` (ligne ~47) :

```swift
    /// (Re)planifie les rappels adaptatifs aux heures données (purge les rappels fixes
    /// et adaptatifs précédents). Plafonné par `AdaptiveReminderPlanner.plafondParJour`.
    func planifierRappelsAdaptatifs(auxHeures heures: [Date]) async
```

- [ ] **Step 2 : Implémenter dans le service réel**

Dans `NotificationService.swift` : ajouter `import WelloKit` en tête (sous `import UserNotifications`). Déclarer les identifiants adaptatifs comme constante statique près des autres (ligne ~12) :

```swift
    private static var idsAdaptatifs: [String] {
        (0..<AdaptiveReminderPlanner.plafondParJour).map { "wello.adaptif.\($0)" }
    }
    private static let idsFixes = ["wello.14h", "wello.17h"]
```

Modifier `planifierRappels` pour purger AUSSI les adaptatifs en tête (remplacer la ligne `center.removePendingNotificationRequests(withIdentifiers: ["wello.14h", "wello.17h"])`) :

```swift
        // On repart d'une ardoise propre : fixes ET adaptatifs (changement de palier possible).
        center.removePendingNotificationRequests(withIdentifiers: Self.idsFixes + Self.idsAdaptatifs)
```

Ajouter la nouvelle méthode (après `planifierRappels`) :

```swift
    func planifierRappelsAdaptatifs(auxHeures heures: [Date]) async {
        // Purge fixes + adaptatifs avant de reposer (recalcul à chaque log/refresh).
        center.removePendingNotificationRequests(withIdentifiers: Self.idsFixes + Self.idsAdaptatifs)
        for (i, date) in heures.prefix(AdaptiveReminderPlanner.plafondParJour).enumerated() {
            let contenu = UNMutableNotificationContent()
            contenu.title = "Hydratation"
            contenu.body = "Tu n'as pas bu depuis un moment — un verre d'eau 💧 ?"
            contenu.categoryIdentifier = Self.catégorieRappel
            contenu.sound = .default
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let req = UNNotificationRequest(identifier: "wello.adaptif.\(i)", content: contenu, trigger: trigger)
            try? await center.add(req)
        }
    }
```

- [ ] **Step 3 : Ajouter au mock**

Dans `Mocks.swift`, dans `struct MockNotificationService`, ajouter :

```swift
    func planifierRappelsAdaptatifs(auxHeures heures: [Date]) async {}
```

- [ ] **Step 4 : Type-check iOS hors Xcode**

Run (la commande complète de la Task 5, Step 4).
Expected: `OK 0 erreur`.

- [ ] **Step 5 : Commit**

```bash
git add Wello/Wello/Services/ServiceProtocols.swift Wello/Wello/Services/NotificationService.swift Wello/Wello/Services/Mocks.swift
git commit -m "feat(premium): planification des notifications adaptatives"
```

---

## Task 7 : App — orchestration dans le store

**Files:**
- Modify: `Wello/Wello/Services/HydrationStore.swift`

- [ ] **Step 1 : Ajouter l'état UI + le planner + le closure d'entitlement**

En tête de `HydrationStore.swift`, après le `struct ÉtatServices` (ligne ~15), ajouter :

```swift
/// Mode courant des rappels, pour le sous-titre du Profil.
enum ModeRappels: Sendable, Equatable { case fixe, apprentissage, adaptatif }

/// État des rappels exposé à l'UI (mode + fenêtre détectée si adaptatif).
struct ÉtatRappels: Sendable, Equatable {
    var mode: ModeRappels = .fixe
    var fenêtre: FenêtreÉveil?
}
```

Dans `final class HydrationStore`, ajouter les propriétés (après `private let calculator = ...`, ligne ~27) :

```swift
    private let planner = AdaptiveReminderPlanner()
    /// Lit le palier au moment de planifier (injecté pour découpler le store de l'EntitlementStore).
    private let rappelsAdaptatifsDébloqués: @MainActor () -> Bool
```

Exposer l'état (après `private(set) var étatServices = ÉtatServices()`, ligne ~34) :

```swift
    /// Mode courant des rappels (lu par le Profil). Mis à jour à chaque replanification.
    private(set) var étatRappels = ÉtatRappels()
```

- [ ] **Step 2 : Étendre l'init**

Modifier la signature de `init` (ligne ~51) pour ajouter le paramètre, avec une valeur par défaut sûre :

```swift
    init(modelContext: ModelContext,
         healthKit: HealthKitServicing,
         weather: WeatherServicing,
         location: LocationServicing,
         notifications: NotificationServicing,
         rappelsAdaptatifsDébloqués: @escaping @MainActor () -> Bool = { false }) {
        self.modelContext = modelContext
        self.healthKit = healthKit
        self.weather = weather
        self.location = location
        self.notifications = notifications
        self.rappelsAdaptatifsDébloqués = rappelsAdaptatifsDébloqués
    }
```

- [ ] **Step 3 : Ajouter le helper de replanification + récupération de l'historique**

Ajouter ces méthodes privées dans la classe (par ex. juste avant `consomméAujourdhui`, ligne ~246) :

```swift
    /// Replanifie les rappels selon le palier : `plus` (avec assez de données) → adaptatif ;
    /// sinon (gratuit ou cold-start) → rappels fixes existants. No-op si rappels désactivés.
    private func planifierSelonPalier(objectifML: Int) async {
        guard profilCourant().remindersEnabled else { return }
        let consommé = consomméAujourdhui()
        let objectifAtteint = consommé >= objectifML

        if rappelsAdaptatifsDébloqués() {
            let historique = historiquePrises()
            if planner.aAssezDeDonnées(historique) {
                let fenêtre = await fenêtreÉveilCourante(historique: historique)
                let heures = planner.planRappels(historique: historique, fenêtre: fenêtre,
                                                 now: .now, objectifAtteint: objectifAtteint)
                étatRappels = ÉtatRappels(mode: .adaptatif, fenêtre: fenêtre)
                await notifications.planifierRappelsAdaptatifs(auxHeures: heures)
                return
            }
            étatRappels = ÉtatRappels(mode: .apprentissage, fenêtre: nil)
        } else {
            étatRappels = ÉtatRappels(mode: .fixe, fenêtre: nil)
        }
        await notifications.planifierRappels(objectifML: objectifML, consomméML: consommé)
    }

    /// Prises des `joursHistoire` jours précédents (today exclu), groupées par jour en
    /// minutes depuis minuit. Sert d'apprentissage des trous habituels.
    private func historiquePrises() -> [JourDePrises] {
        let cal = Calendar.current
        let finExclue = cal.startOfDay(for: .now)
        guard let début = cal.date(byAdding: .day, value: -AdaptiveReminderPlanner.joursHistoire, to: finExclue)
        else { return [] }
        let descripteur = FetchDescriptor<HydrationLog>(
            predicate: #Predicate { $0.loggedAt >= début && $0.loggedAt < finExclue }
        )
        let logs = (try? modelContext.fetch(descripteur)) ?? []
        let parJour = Dictionary(grouping: logs) { cal.startOfDay(for: $0.loggedAt) }
        return parJour.values.map { duJour in
            JourDePrises(minutesDePrise: duJour.map {
                let c = cal.dateComponents([.hour, .minute], from: $0.loggedAt)
                return (c.hour ?? 0) * 60 + (c.minute ?? 0)
            })
        }
    }

    /// Fenêtre d'éveil : sommeil HealthKit → historique → défaut.
    private func fenêtreÉveilCourante(historique: [JourDePrises]) async -> FenêtreÉveil {
        let cal = Calendar.current
        let début = cal.date(byAdding: .day, value: -AdaptiveReminderPlanner.joursHistoire, to: .now) ?? .now
        let périodes = await healthKit.périodesSommeil(depuis: début)
        if let f = planner.fenêtreDepuisSommeil(périodes) { return f }
        if let f = planner.fenêtreDepuisHistorique(historique) { return f }
        return .défaut
    }
```

- [ ] **Step 4 : Router les 4 appels existants via le helper**

Remplacer les appels directs à `notifications.planifierRappels(...)` :

Dans `refreshToday` (ligne ~116-120), remplacer le bloc :

```swift
        if profil.remindersEnabled {
            _ = await notifications.requestAuthorization()
            await notifications.planifierRappels(objectifML: resultat.totalML, consomméML: consomméAujourdhui())
            await détecterPostSéance()
        }
```

par :

```swift
        if profil.remindersEnabled {
            _ = await notifications.requestAuthorization()
            await planifierSelonPalier(objectifML: resultat.totalML)
            await détecterPostSéance()
        }
```

Dans `log` (ligne ~207-209), remplacer :

```swift
        if let objectif = breakdown?.totalML {
            await notifications.planifierRappels(objectifML: objectif, consomméML: consomméAujourdhui())
        }
```

par :

```swift
        if let objectif = breakdown?.totalML {
            await planifierSelonPalier(objectifML: objectif)
        }
```

Faire le **même remplacement** dans `annulerDernièrePrise` (ligne ~228-230) et dans `supprimer` (ligne ~241-243) — les deux ont le bloc `if let objectif = breakdown?.totalML { await notifications.planifierRappels(...) }` identique, à remplacer par `if let objectif = breakdown?.totalML { await planifierSelonPalier(objectifML: objectif) }`.

- [ ] **Step 5 : Type-check iOS hors Xcode**

Run (commande complète de la Task 5, Step 4).
Expected: `OK 0 erreur`.

- [ ] **Step 6 : Commit**

```bash
git add Wello/Wello/Services/HydrationStore.swift
git commit -m "feat(premium): orchestration des rappels adaptatifs dans le store"
```

---

## Task 8 : App — câblage du palier dans WelloApp

**Files:**
- Modify: `Wello/Wello/App/WelloApp.swift`

- [ ] **Step 1 : Créer l'entitlement store avant le store et l'injecter**

Dans `WelloApp.init()` (lignes ~15-28), réordonner pour construire `entitlements` d'abord, puis passer le closure au store. Remplacer le bloc :

```swift
        let store = HydrationStore(
            modelContext: container.mainContext,
            healthKit: HealthKitService(),
            weather: WeatherService(),
            location: LocationService(),
            notifications: NotificationService()
        )
        _store = State(initialValue: store)
        _entitlements = State(initialValue: EntitlementStore(store: StoreKitService()))
        _drinks = State(initialValue: DrinkCatalog())
```

par :

```swift
        let entitlements = EntitlementStore(store: StoreKitService())
        let store = HydrationStore(
            modelContext: container.mainContext,
            healthKit: HealthKitService(),
            weather: WeatherService(),
            location: LocationService(),
            notifications: NotificationService(),
            rappelsAdaptatifsDébloqués: { entitlements.isUnlocked(.adaptiveReminders) }
        )
        _store = State(initialValue: store)
        _entitlements = State(initialValue: entitlements)
        _drinks = State(initialValue: DrinkCatalog())
```

- [ ] **Step 2 : Type-check iOS hors Xcode**

Run (commande complète de la Task 5, Step 4).
Expected: `OK 0 erreur`.

> Note : `EntitlementStore` est `@MainActor` et `WelloApp.init` s'exécute sur le main thread ; le closure capture `entitlements` (référence de classe) et le lit à la planification — cohérent avec l'isolation `@MainActor` du store.

- [ ] **Step 3 : Commit**

```bash
git add Wello/Wello/App/WelloApp.swift
git commit -m "feat(premium): branche le palier adaptatif dans WelloApp"
```

---

## Task 9 : App — UI du Profil (sous-titre + teaser)

**Files:**
- Modify: `Wello/Wello/Views/ProfileView.swift` (section « Rappels », lignes ~157-169)

- [ ] **Step 1 : Remplacer la Section des rappels**

Remplacer la `Section` du toggle « Rappels intelligents » (lignes ~157-169) par :

```swift
                    Section {
                        Toggle(isOn: Binding(
                            get: { profil.remindersEnabled },
                            set: { actif in
                                profil.remindersEnabled = actif
                                profil.updatedAt = .now
                                // Désactivation immédiate : on annule les rappels déjà programmés.
                                if !actif { Task { await store.couperRappelsAujourdhui() } }
                            })) {
                            label("Rappels intelligents", nil, icon: "bell.fill", teinte: WelloTheme.accentDeep)
                        }
                        if !entitlements.isUnlocked(.adaptiveReminders) {
                            Button {
                                paywall = true
                            } label: {
                                HStack {
                                    label("Rappels adaptatifs", nil,
                                          icon: "sparkles", teinte: WelloTheme.accentDeep)
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
                            .accessibilityLabel("Rappels adaptatifs, débloquer")
                            .accessibilityHint("Ouvre l'offre Wello+")
                        }
                    } footer: {
                        Text(sousTitreRappels)
                            .font(.system(.caption, design: .rounded))
                    }
```

- [ ] **Step 2 : Ajouter la propriété calculée du sous-titre**

Ajouter dans `struct ProfileView` (près de `private var profil`, ligne ~16) :

```swift
    /// Sous-titre contextuel de la section Rappels selon le palier et le mode courant.
    private var sousTitreRappels: String {
        guard entitlements.isUnlocked(.adaptiveReminders) else {
            return "Rappels à heures fixes. Passe à Wello+ pour des rappels adaptés à tes habitudes."
        }
        switch store.étatRappels.mode {
        case .apprentissage:
            return "On apprend tes habitudes… (rappels classiques en attendant)."
        case .adaptatif:
            if let f = store.étatRappels.fenêtre {
                return "Rappels intelligents — basés sur tes habitudes. Fenêtre détectée ~\(f.réveilMin / 60)h–\(f.coucherMin / 60)h."
            }
            return "Rappels intelligents — basés sur tes habitudes et ta fenêtre d'éveil."
        case .fixe:
            return "Rappels intelligents — basés sur tes habitudes et ta fenêtre d'éveil."
        }
    }
```

- [ ] **Step 3 : Vérifier l'import WelloKit**

`ProfileView.swift` importe déjà `WelloKit` (ligne 3). `FenêtreÉveil` est donc accessible. Aucune action si l'import est présent.

- [ ] **Step 4 : Type-check iOS hors Xcode**

Run (commande complète de la Task 5, Step 4).
Expected: `OK 0 erreur`.

- [ ] **Step 5 : Commit**

```bash
git add Wello/Wello/Views/ProfileView.swift
git commit -m "feat(premium): sous-titre d'état + teaser des rappels adaptatifs au Profil"
```

---

## Task 10 : App — previews + vérification finale

**Files:**
- Modify: `Wello/Wello/Views/PreviewSupport.swift:35-41` (`store` factory)

- [ ] **Step 1 : Étendre la factory store des previews**

Dans `PreviewSupport.swift`, remplacer la méthode `store(_:)` par une version paramétrée (le palier des rappels) :

```swift
    /// Store sur mocks, pour des previews réalistes (objectif calculé, jauge remplie).
    /// `premiumRappels` simule le déblocage des rappels adaptatifs.
    static func store(_ container: ModelContainer, premiumRappels: Bool = false) -> HydrationStore {
        HydrationStore(modelContext: container.mainContext,
                       healthKit: MockHealthKitService(),
                       weather: MockWeatherService(),
                       location: MockLocationService(),
                       notifications: MockNotificationService(),
                       rappelsAdaptatifsDébloqués: { premiumRappels })
    }
```

> Les appels existants `PreviewSupport.store(container)` restent valides (paramètre par défaut).

- [ ] **Step 2 : Type-check iOS hors Xcode (final)**

Run (commande complète de la Task 5, Step 4).
Expected: `OK 0 erreur`.

- [ ] **Step 3 : Suite complète WelloKit (final)**

Run: `cd WelloKit && swift test`
Expected: PASS (toutes suites, dont `AdaptiveReminders`).

- [ ] **Step 4 : Commit**

```bash
git add Wello/Wello/Views/PreviewSupport.swift
git commit -m "feat(premium): factory de preview avec palier rappels adaptatifs"
```

---

## Vérification finale (récap)

- `cd WelloKit && swift test` → toutes suites au vert (logique pure des trous + fenêtres).
- Type-check iOS hors Xcode → `OK 0 erreur` (services, store, app, vues).
- **Étapes Xcode manuelles (de ton côté)** : aucune nouvelle (HealthKit déjà lié, `NSHealthShareUsageDescription` présent). Test sandbox du flux de notifications réel dans Xcode.

## Notes de réglage

Constantes dans `AdaptiveReminderPlanner` (à ajuster à l'usage) : `minGapMin` (120),
`seuilRécurrence` (0.40), `leadTimeMin` (15), `espacementMin` (90), `plafondParJour` (6),
`joursHistoire` (14), `minJoursPourAdaptatif` (7).
