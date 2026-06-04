# Analyses détaillées Wello+ — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Livrer la feature premium « Analyses et tendances » : un écran dédié `AnalyticsView` (taux d'atteinte 7/30 j, tendance, meilleure série, répartition horaire), accessible depuis l'Historique et gaté via `.analytics`.

**Architecture:** Logique d'agrégation pure et testée dans `WelloKit` (`HydrationStats` + `DayPeriod`) ; vue SwiftUI MV lisant `@Query` et déléguant tout calcul au kit ; point d'entrée dans `HistoryView` (NavigationLink en premium, `PremiumGateCard` → paywall en gratuit). L'infra premium (StoreKit, `EntitlementStore`, `PremiumFeature.analytics`, paywall) existe déjà et n'est pas modifiée.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, Swift Charts, Swift Testing (`swift test`). Patterns existants : `HydrationStats` (fonctions pures), `CardContainer`/`WelloTheme`, gating `entitlements.isUnlocked(_:)`.

**Spec :** `docs/superpowers/specs/2026-06-04-wello-analyses-design.md`.

> **Note dépôt git :** cet environnement n'est **pas** un dépôt git. Les étapes `git commit` sont
> fournies pour cohérence avec les plans existants ; à exécuter seulement si/quand un dépôt existe,
> sinon les ignorer. La vérification réelle passe par `swift test` + le type-check iOS hors Xcode.

**Note de vérification :** la commande de type-check du `CLAUDE.md` utilise des globs
(`WelloKit/Sources/WelloKit/*.swift`, `.../Models/*.swift`, `Wello/Wello/Views/*.swift`, …) → les
nouveaux fichiers sont pris en compte automatiquement. Bloc « type-check iOS » référencé ci-dessous :

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
- `WelloKit/Sources/WelloKit/Models/DayPeriod.swift` — enum des tranches de journée + `from(hour:)` + `label`.
- `Wello/Wello/Views/AnalyticsView.swift` — écran d'analyses premium.

**Modifiés :**
- `WelloKit/Sources/WelloKit/HydrationStats.swift` — ajout `reachRate`, `bestStreak`, `hydrationByPeriod`.
- `WelloKit/Tests/WelloKitTests/HydrationStatsTests.swift` — tests des nouvelles fonctions.
- `Wello/Wello/Views/HistoryView.swift` — entrée « Analyses détaillées » (NavigationLink / gate card).

**Inchangés (réutilisés) :** `Premium.swift` (`.analytics` déjà déclaré), `PaywallView.swift`
(`PremiumGateCard`, déjà vend « Analyses et tendances »), `EntitlementStore.swift`,
`PreviewSupport.swift`, `Theme.swift` (`CardContainer`, `WelloTheme`, `welloBackground`).

---

## Task 1 : `reachRate` + `bestStreak` (WelloKit, TDD)

**Files:**
- Test: `WelloKit/Tests/WelloKitTests/HydrationStatsTests.swift`
- Modify: `WelloKit/Sources/WelloKit/HydrationStats.swift`

- [ ] **Step 1 : Écrire les tests qui échouent**

Ajouter dans le `struct HydrationStatsTests` (le helper `jour(_:_:)` existe déjà dans ce fichier) :

```swift
    @Test("reachRate : liste vide → 0")
    func tauxVide() {
        #expect(HydrationStats.reachRate([]) == 0)
    }

    @Test("reachRate : 3 jours atteints sur 4 → 0.75")
    func tauxPartiel() {
        let days = [jour(2600, 2500), jour(1000, 2500), jour(2500, 2500), jour(3000, 2500)]
        #expect(HydrationStats.reachRate(days) == 0.75)
    }

    @Test("reachRate : tous atteints → 1.0")
    func tauxComplet() {
        let days = [jour(2600, 2500), jour(2700, 2500)]
        #expect(HydrationStats.reachRate(days) == 1.0)
    }

    @Test("bestStreak : liste vide → 0")
    func recordVide() {
        #expect(HydrationStats.bestStreak([]) == 0)
    }

    @Test("bestStreak : record au milieu d'une séquence")
    func recordMilieu() {
        // ✓ ✗ ✓ ✓ ✓ ✗ ✓  → record = 3
        let days = [jour(2600, 2500), jour(1000, 2500), jour(2600, 2500), jour(2600, 2500),
                    jour(2600, 2500), jour(1000, 2500), jour(2600, 2500)]
        #expect(HydrationStats.bestStreak(days) == 3)
    }

    @Test("bestStreak : tous atteints → n")
    func recordComplet() {
        let days = [jour(2600, 2500), jour(2700, 2500), jour(2800, 2500)]
        #expect(HydrationStats.bestStreak(days) == 3)
    }
```

- [ ] **Step 2 : Lancer les tests pour vérifier l'échec**

Run: `cd WelloKit && swift test --filter HydrationStats`
Expected: FAIL — `type 'HydrationStats' has no member 'reachRate' / 'bestStreak'`.

- [ ] **Step 3 : Écrire l'implémentation**

Dans `WelloKit/Sources/WelloKit/HydrationStats.swift`, ajouter ces deux fonctions dans l'`enum HydrationStats` (après `averageConsumed`) :

```swift
    /// Fraction de jours ayant atteint l'objectif (0…1). 0 si la liste est vide.
    /// L'appelant passe la fenêtre voulue, ex. `Array(days.prefix(7))`.
    public static func reachRate(_ days: [DailyTotal]) -> Double {
        guard !days.isEmpty else { return 0 }
        let atteints = days.filter(\.reached).count
        return Double(atteints) / Double(days.count)
    }

    /// Plus longue série de jours consécutifs atteints, sur toute la liste fournie.
    /// Indépendant du sens d'ordre (ne dépend que de la contiguïté dans la liste passée).
    public static func bestStreak(_ days: [DailyTotal]) -> Int {
        var record = 0
        var courant = 0
        for d in days {
            if d.reached {
                courant += 1
                record = max(record, courant)
            } else {
                courant = 0
            }
        }
        return record
    }
```

- [ ] **Step 4 : Lancer les tests pour vérifier le succès**

Run: `cd WelloKit && swift test --filter HydrationStats`
Expected: PASS (anciens + 6 nouveaux tests).

- [ ] **Step 5 : Commit** *(si dépôt git ; sinon ignorer)*

```bash
git add WelloKit/Sources/WelloKit/HydrationStats.swift WelloKit/Tests/WelloKitTests/HydrationStatsTests.swift
git commit -m "feat(kit): reachRate + bestStreak (TDD)"
```

---

## Task 2 : `DayPeriod` + `hydrationByPeriod` (WelloKit, TDD)

**Files:**
- Create: `WelloKit/Sources/WelloKit/Models/DayPeriod.swift`
- Modify: `WelloKit/Sources/WelloKit/HydrationStats.swift`
- Test: `WelloKit/Tests/WelloKitTests/HydrationStatsTests.swift`

- [ ] **Step 1 : Écrire les tests qui échouent**

Ajouter dans le `struct HydrationStatsTests` :

```swift
    @Test("DayPeriod.from : bornes des tranches")
    func tranchesHoraires() {
        #expect(DayPeriod.from(hour: 0) == .nuit)
        #expect(DayPeriod.from(hour: 5) == .nuit)
        #expect(DayPeriod.from(hour: 6) == .matin)
        #expect(DayPeriod.from(hour: 10) == .matin)
        #expect(DayPeriod.from(hour: 11) == .midi)
        #expect(DayPeriod.from(hour: 13) == .midi)
        #expect(DayPeriod.from(hour: 14) == .apresMidi)
        #expect(DayPeriod.from(hour: 17) == .apresMidi)
        #expect(DayPeriod.from(hour: 18) == .soiree)
        #expect(DayPeriod.from(hour: 22) == .soiree)
        #expect(DayPeriod.from(hour: 23) == .nuit)
    }

    @Test("hydrationByPeriod : renvoie toujours 5 tranches dans l'ordre canonique")
    func répartitionOrdre() {
        let r = HydrationStats.hydrationByPeriod([])
        #expect(r.map(\.period) == [.matin, .midi, .apresMidi, .soiree, .nuit])
        #expect(r.allSatisfy { $0.ml == 0 })
    }

    @Test("hydrationByPeriod : agrège les ml par tranche")
    func répartitionSomme() {
        let entries: [(hour: Int, ml: Int)] = [
            (8, 250), (9, 250),   // matin = 500
            (13, 300),            // midi = 300
            (20, 500),            // soirée = 500
        ]
        let r = HydrationStats.hydrationByPeriod(entries)
        let parTranche = Dictionary(uniqueKeysWithValues: r.map { ($0.period, $0.ml) })
        #expect(parTranche[.matin] == 500)
        #expect(parTranche[.midi] == 300)
        #expect(parTranche[.apresMidi] == 0)
        #expect(parTranche[.soiree] == 500)
        #expect(parTranche[.nuit] == 0)
    }
```

- [ ] **Step 2 : Lancer les tests pour vérifier l'échec**

Run: `cd WelloKit && swift test --filter HydrationStats`
Expected: FAIL — `cannot find 'DayPeriod' in scope` / `has no member 'hydrationByPeriod'`.

- [ ] **Step 3 : Créer `DayPeriod.swift`**

Create `WelloKit/Sources/WelloKit/Models/DayPeriod.swift` :

```swift
import Foundation

/// Tranches de la journée pour la répartition horaire des prises d'eau.
/// L'ordre de déclaration est l'ordre canonique d'affichage (matin → nuit).
public enum DayPeriod: String, Sendable, CaseIterable {
    case matin       // 6–11
    case midi        // 11–14
    case apresMidi   // 14–18
    case soiree      // 18–23
    case nuit        // 23–6 (enveloppe minuit)

    /// Tranche correspondant à une heure (0…23).
    public static func from(hour: Int) -> DayPeriod {
        switch hour {
        case 6..<11:  return .matin
        case 11..<14: return .midi
        case 14..<18: return .apresMidi
        case 18..<23: return .soiree
        default:      return .nuit   // 23 et 0–5
        }
    }

    /// Libellé court français pour l'affichage.
    public var label: String {
        switch self {
        case .matin:     return "Matin"
        case .midi:      return "Midi"
        case .apresMidi: return "Après-midi"
        case .soiree:    return "Soirée"
        case .nuit:      return "Nuit"
        }
    }
}
```

- [ ] **Step 4 : Ajouter `hydrationByPeriod`**

Dans `WelloKit/Sources/WelloKit/HydrationStats.swift`, ajouter dans l'`enum HydrationStats` (après `bestStreak`) :

```swift
    /// Somme des ml par tranche de journée. Renvoie toujours les 5 tranches dans l'ordre
    /// canonique (matin→nuit), à 0 si aucune prise. `entries` = (heure 0…23, ml).
    public static func hydrationByPeriod(_ entries: [(hour: Int, ml: Int)]) -> [(period: DayPeriod, ml: Int)] {
        var sommes: [DayPeriod: Int] = [:]
        for e in entries {
            sommes[DayPeriod.from(hour: e.hour), default: 0] += e.ml
        }
        return DayPeriod.allCases.map { (period: $0, ml: sommes[$0] ?? 0) }
    }
```

- [ ] **Step 5 : Lancer les tests pour vérifier le succès**

Run: `cd WelloKit && swift test --filter HydrationStats`
Expected: PASS (tous).

- [ ] **Step 6 : Commit** *(si dépôt git ; sinon ignorer)*

```bash
git add WelloKit/Sources/WelloKit/Models/DayPeriod.swift WelloKit/Sources/WelloKit/HydrationStats.swift WelloKit/Tests/WelloKitTests/HydrationStatsTests.swift
git commit -m "feat(kit): DayPeriod + hydrationByPeriod (TDD)"
```

---

## Task 3 : `AnalyticsView` (app)

**Files:**
- Create: `Wello/Wello/Views/AnalyticsView.swift`

- [ ] **Step 1 : Créer `AnalyticsView.swift`**

Create `Wello/Wello/Views/AnalyticsView.swift` :

```swift
import SwiftUI
import SwiftData
import Charts
import WelloKit

/// Écran d'analyses détaillées (Wello+) : taux d'atteinte, tendance, meilleure série,
/// répartition horaire. Pattern MV : lit @Query et délègue tout calcul à HydrationStats.
struct AnalyticsView: View {
    @Query(sort: \DailyGoal.date, order: .reverse) private var objectifs: [DailyGoal]
    @Query private var logs: [HydrationLog]

    var body: some View {
        Group {
            if objectifs.isEmpty {
                étatVide
            } else {
                contenu
            }
        }
        .welloBackground()
        .navigationTitle("Analyses")
    }

    private var contenu: some View {
        let totals = totalsParJour()
        return ScrollView {
            LazyVStack(spacing: 16) {
                tauxCard(totals)
                tendanceCard(totals)
                meilleureSérieCard(totals)
                répartitionCard()
            }
            .padding()
        }
    }

    // MARK: Données

    /// Consommé (ml) par jour, agrégé en un seul passage sur les logs.
    private func consommationParJour() -> [Date: Int] {
        let cal = Calendar.current
        var map: [Date: Int] = [:]
        for log in logs {
            map[cal.startOfDay(for: log.loggedAt), default: 0] += log.amountML
        }
        return map
    }

    /// Totaux jour (consommé vs objectif), du plus récent au plus ancien.
    private func totalsParJour() -> [DailyTotal] {
        let conso = consommationParJour()
        let cal = Calendar.current
        return objectifs.map { goal in
            DailyTotal(consumedML: conso[cal.startOfDay(for: goal.date)] ?? 0, goalML: goal.totalML)
        }
    }

    /// (heure, ml) des prises sur les 30 derniers jours, pour la répartition.
    private func entréesHoraires() -> [(hour: Int, ml: Int)] {
        let cal = Calendar.current
        let borne = cal.date(byAdding: .day, value: -29, to: cal.startOfDay(for: .now))!
        return logs
            .filter { $0.loggedAt >= borne }
            .map { (hour: cal.component(.hour, from: $0.loggedAt), ml: $0.amountML) }
    }

    // MARK: Cartes

    private func tauxCard(_ totals: [DailyTotal]) -> some View {
        let taux7 = HydrationStats.reachRate(Array(totals.prefix(7)))
        let taux30 = HydrationStats.reachRate(Array(totals.prefix(30)))
        return CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                titre("Taux d'atteinte")
                HStack(spacing: 12) {
                    tuile(pourcent(taux7), "sur 7 jours", "target", WelloTheme.accent)
                    tuile(pourcent(taux30), "sur 30 jours", "target", WelloTheme.accentDeep)
                }
            }
        }
    }

    private func tendanceCard(_ totals: [DailyTotal]) -> some View {
        let moy7 = HydrationStats.averageConsumed(totals, lastN: 7)
        let moy30 = HydrationStats.averageConsumed(totals, lastN: 30)
        let hausse = moy7 >= moy30
        let delta = abs(moy7 - moy30)
        return CardContainer {
            VStack(alignment: .leading, spacing: 8) {
                titre("Tendance")
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(litres(moy7))
                        .font(.system(.title, design: .rounded).weight(.bold))
                        .foregroundStyle(WelloTheme.ink)
                    Image(systemName: hausse ? "arrow.up.right" : "arrow.down.right")
                        .foregroundStyle(hausse ? .green : .orange)
                    Text("\(hausse ? "+" : "−")\(litres(delta)) vs 30 j")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(WelloTheme.inkSoft)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tendance : moyenne 7 jours \(litres(moy7)), \(hausse ? "en hausse de" : "en baisse de") \(litres(delta)) par rapport à la moyenne 30 jours")
    }

    private func meilleureSérieCard(_ totals: [DailyTotal]) -> some View {
        let record = HydrationStats.bestStreak(totals)
        return CardContainer {
            HStack(spacing: 14) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(record) jours")
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .foregroundStyle(WelloTheme.ink)
                    Text("meilleure série (record)")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(WelloTheme.inkSoft)
                }
                Spacer()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Meilleure série : record de \(record) jours")
    }

    private func répartitionCard() -> some View {
        let répartition = HydrationStats.hydrationByPeriod(entréesHoraires())
        let total = répartition.reduce(0) { $0 + $1.ml }
        return CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                titre("Répartition horaire (30 j)")
                if total == 0 {
                    Text("Aucune prise enregistrée sur les 30 derniers jours.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(WelloTheme.inkSoft)
                } else {
                    Chart {
                        ForEach(répartition, id: \.period) { tranche in
                            BarMark(
                                x: .value("Tranche", tranche.period.label),
                                y: .value("ml", tranche.ml)
                            )
                            .foregroundStyle(WelloTheme.accent)
                            .cornerRadius(4)
                            .accessibilityLabel(tranche.period.label)
                            .accessibilityValue("\(tranche.ml) millilitres")
                        }
                    }
                    .frame(height: 170)
                }
            }
        }
    }

    // MARK: Helpers présentation

    private func titre(_ texte: String) -> some View {
        Text(texte)
            .font(.system(.headline, design: .rounded))
            .foregroundStyle(WelloTheme.ink)
    }

    private func tuile(_ valeur: String, _ légende: String, _ icon: String, _ teinte: Color) -> some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: icon).foregroundStyle(teinte)
                Text(valeur)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(WelloTheme.ink)
                Text(légende)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(WelloTheme.inkSoft)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(légende) : \(valeur)")
    }

    private func pourcent(_ ratio: Double) -> String {
        "\(Int((ratio * 100).rounded()))%"
    }

    private func litres(_ ml: Int) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.maximumFractionDigits = 1
        return (f.string(from: NSNumber(value: Double(ml) / 1000)) ?? "0") + " L"
    }

    private var étatVide: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 44))
                .foregroundStyle(WelloTheme.accent.opacity(0.6))
            Text("Pas encore d'analyses")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(WelloTheme.ink)
            Text("Tes tendances apparaîtront ici au fil des jours de suivi.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(WelloTheme.inkSoft)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        AnalyticsView()
            .modelContainer(PreviewSupport.container())
    }
}
#endif
```

> Note DRY : `consommationParJour()` et `litres(_:)` reprennent les helpers privés homonymes de
> `HistoryView`. Duplication assumée (helpers privés, deux vues auto-contenues) — pas d'extraction
> dans cette itération (YAGNI).

- [ ] **Step 2 : Type-check iOS**

Run la commande de type-check complète (voir en-tête du plan).
Expected: 0 erreur.

- [ ] **Step 3 : Commit** *(si dépôt git ; sinon ignorer)*

```bash
git add Wello/Wello/Views/AnalyticsView.swift
git commit -m "feat(premium): écran AnalyticsView (taux, tendance, série, répartition)"
```

---

## Task 4 : Point d'entrée « Analyses détaillées » dans l'Historique

**Files:**
- Modify: `Wello/Wello/Views/HistoryView.swift`

- [ ] **Step 1 : Ajouter l'entrée dans `contenu`**

Modify `Wello/Wello/Views/HistoryView.swift`. Dans la propriété `contenu`, le `LazyVStack` contient
actuellement `statsCard(conso)` suivi du `ForEach(objectifsVisibles)`. Insérer `analyseEntrée`
**juste après** `statsCard(conso)` :

```swift
                if premium { sélecteurPlage }
                grapheCard(conso)
                statsCard(conso)
                analyseEntrée
                ForEach(objectifsVisibles) { goal in
```

- [ ] **Step 2 : Ajouter la propriété `analyseEntrée`**

Toujours dans `HistoryView`, ajouter cette propriété (par ex. juste après `contenu`) :

```swift
    /// Accès aux analyses détaillées : NavigationLink en premium, carte de teasing en gratuit.
    @ViewBuilder
    private var analyseEntrée: some View {
        if entitlements.isUnlocked(.analytics) {
            NavigationLink {
                AnalyticsView()
            } label: {
                CardContainer {
                    HStack(spacing: 14) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 20))
                            .foregroundStyle(WelloTheme.accent)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Analyses détaillées")
                                .font(.system(.headline, design: .rounded))
                                .foregroundStyle(WelloTheme.ink)
                            Text("Taux d'atteinte, tendance, répartition")
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
            .accessibilityLabel("Analyses détaillées")
            .accessibilityHint("Ouvre les analyses et tendances")
        } else {
            PremiumGateCard(bénéfice: "Analyses et tendances détaillées") {
                paywall = true
            }
        }
    }
```

> `entitlements`, `paywall` (`@State`) et le `.sheet(isPresented: $paywall) { PaywallView(...) }`
> existent déjà dans `HistoryView` (utilisés par le gating d'historique) — rien à ajouter pour le
> paywall. `PremiumGateCard` vient de `PaywallView.swift` (déjà dans le target).

- [ ] **Step 3 : Type-check iOS**

Run la commande de type-check complète.
Expected: 0 erreur.

- [ ] **Step 4 : Commit** *(si dépôt git ; sinon ignorer)*

```bash
git add Wello/Wello/Views/HistoryView.swift
git commit -m "feat(premium): entrée Analyses détaillées dans l'Historique (gate .analytics)"
```

---

## Vérification finale

- [ ] **Logique pure :** `cd WelloKit && swift test` → tout passe (suite `HydrationStats` étendue :
  `reachRate`, `bestStreak`, `DayPeriod.from`, `hydrationByPeriod`).
- [ ] **App iOS :** la commande de type-check complète → 0 erreur.
- [ ] **Previews (Xcode, manuel) :**
  - `AnalyticsView` (preview) affiche les 4 cartes (avec données d'exemple du `PreviewSupport`).
  - `HistoryView` « Gratuit » montre la `PremiumGateCard` « Analyses et tendances détaillées ».
  - `HistoryView` « Wello+ » montre la carte cliquable « Analyses détaillées » → pousse `AnalyticsView`.

## Étapes Xcode manuelles (hors CLI)

- Ajouter `AnalyticsView.swift` au target `Wello` (groupes synchronisés Xcode 16+ : automatique).
- `DayPeriod.swift` est dans le package `WelloKit` (déjà lié) : pris en compte automatiquement.
- Aucune capability ni clé Info.plist nouvelle (pas de StoreKit/HealthKit/réseau ajouté).

---

## Self-Review (effectuée)

**Couverture de la spec :**
- Taux d'atteinte 7/30 j → `reachRate` (Task 1) + `tauxCard` (Task 3) ✅
- Tendance 7 vs 30 j → `averageConsumed` (existant) + `tendanceCard` (Task 3) ✅
- Meilleure série → `bestStreak` (Task 1) + `meilleureSérieCard` (Task 3) ✅
- Répartition horaire 30 j → `DayPeriod`/`hydrationByPeriod` (Task 2) + `répartitionCard` (Task 3) ✅
- Écran dédié + gating `.analytics` + teasing paywall → Task 4 ✅
- Cas limites (vide, < 7/30 j via `prefix`, aucune prise → état vide) → Tasks 3 (`étatVide`,
  garde `total == 0`) + bornes `prefix` ✅
- Logique testable CLI → Tasks 1–2 en TDD ✅

**Placeholders :** aucun — chaque étape contient le code réel.

**Cohérence des types :** `DailyTotal`, `reachRate`, `bestStreak`, `averageConsumed`,
`DayPeriod` (+ `.from(hour:)`, `.label`, `.allCases`), `hydrationByPeriod` (tuples `(period:, ml:)`)
sont définis en Tasks 1–2 et utilisés à l'identique dans `AnalyticsView` (Task 3). `CardContainer`,
`WelloTheme.*`, `welloBackground()`, `PremiumGateCard`, `entitlements.isUnlocked(.analytics)`,
`paywall`/`.sheet` réutilisent l'existant vérifié dans `Theme.swift`, `PaywallView.swift`,
`HistoryView.swift`.
