# Analyses détaillées Wello+ — Design

**Statut :** validé (brainstorming), prêt pour plan d'implémentation.
**Date :** 2026-06-04.

## But

Livrer la feature premium **« Analyses et tendances »**, déjà promise par le paywall et déjà
déclarée comme cas `.analytics` dans `PremiumFeature`. Un écran dédié `AnalyticsView`, accessible
depuis l'Historique, qui apporte de la **profondeur d'analyse au-delà** des stats déjà offertes
gratuitement (série en cours + moyenne 7 j + graphe d'atteinte).

## Principes / contraintes héritées

- **Logique d'agrégation dans `WelloKit`**, en fonctions pures `Sendable` sans dépendance Apple
  framework → testables en CLI (`swift test`), conformément au `CLAUDE.md`.
- **Pattern MV** : pas de ViewModel ; `AnalyticsView` lit `@Query` (`DailyGoal`, `HydrationLog`)
  et délègue tout calcul à `HydrationStats`.
- **Gating** via `entitlements.isUnlocked(.analytics)` : l'infra premium existe déjà, rien à
  ajouter côté StoreKit/EntitlementStore/PaywallView.
- **Dégradation gracieuse** : peu/pas de données → états vides propres, jamais de crash ni de
  division par zéro.
- App **100 % locale, francophone** : nombres/dates en `fr_FR`, litres avec 1 décimale.

## Périmètre

### Inclus

1. **Taux d'atteinte 7 j / 30 j** — % de jours où l'objectif a été atteint.
2. **Tendance** — moyenne consommée 7 j vs 30 j, avec flèche ↑/↓ et delta en litres.
3. **Meilleure série (record)** — plus longue série de jours atteints de tout l'historique.
4. **Répartition horaire (30 j)** — quelle part de l'eau est bue à quelle tranche de la journée.

### Exclu (YAGNI pour cette itération)

- Régularité par jour de la semaine.
- Filtres de période personnalisés (au-delà des fenêtres 7/30 j fixes).
- Export depuis l'écran Analyses (c'est la feature `.export`, séparée).

## Architecture

### 1. Logique pure — `WelloKit/Sources/WelloKit/HydrationStats.swift`

Ajouts à l'`enum HydrationStats` (les types `DailyTotal` existants sont réutilisés) :

```swift
/// Fraction de jours ayant atteint l'objectif (0…1). 0 si la liste est vide.
/// L'appelant passe la fenêtre voulue, ex. Array(days.prefix(7)).
static func reachRate(_ days: [DailyTotal]) -> Double

/// Plus longue série de jours consécutifs atteints, sur toute la liste fournie.
/// Indépendant de l'ordre (ne dépend que de la contiguïté dans la liste passée).
static func bestStreak(_ days: [DailyTotal]) -> Int
```

`averageConsumed(_:lastN:)` existant est réutilisé pour la tendance (7 j et 30 j) ; le delta se
calcule dans la vue.

Nouveau fichier **`WelloKit/Sources/WelloKit/Models/DayPeriod.swift`** :

```swift
/// Tranches de la journée pour la répartition horaire des prises d'eau.
public enum DayPeriod: String, Sendable, CaseIterable {
    case matin       // 6–11
    case midi        // 11–14
    case apresMidi   // 14–18
    case soiree      // 18–23
    case nuit        // 23–6 (enveloppe minuit)

    /// Tranche correspondant à une heure (0…23).
    public static func from(hour: Int) -> DayPeriod

    /// Libellé court français pour l'affichage.
    public var label: String
}
```

Nouvelle fonction pure dans `HydrationStats` :

```swift
/// Somme des ml par tranche de journée. Renvoie toujours les 5 tranches dans l'ordre
/// canonique (matin→nuit), à 0 si aucune prise. `entries` = (heure 0…23, ml).
static func hydrationByPeriod(_ entries: [(hour: Int, ml: Int)]) -> [(period: DayPeriod, ml: Int)]
```

### 2. Vue — `Wello/Wello/Views/AnalyticsView.swift` (nouveau)

- `@Query(sort: \DailyGoal.date, order: .reverse) private var objectifs: [DailyGoal]`
- `@Query private var logs: [HydrationLog]`
- Agrégation en un seul passage sur les logs (même approche `consommationParJour()` que `HistoryView`).
- `totals: [DailyTotal]` construit depuis `objectifs` (du plus récent au plus ancien) + consommé/jour.
- Cartes (`CardContainer`, `WelloTheme`) dans l'ordre :
  1. **Taux d'atteinte** — deux tuiles : `reachRate(prefix(7))` et `reachRate(prefix(30))`, en %.
  2. **Tendance** — `averageConsumed(lastN: 7)` vs `averageConsumed(lastN: 30)` ; flèche ↑ si 7 j ≥ 30 j sinon ↓ ; delta affiché en litres (`|moy7 − moy30|`).
  3. **Meilleure série** — `bestStreak(totals)`, présentée comme record (icône `flame.fill`).
  4. **Répartition horaire (30 j)** — graphe `Charts` (`BarMark` par `DayPeriod`) sur les logs des
     30 derniers jours, via `hydrationByPeriod`. État vide si aucune prise sur la fenêtre.
- **Accessibilité** : chaque tuile expose un `accessibilityLabel`/`Value` explicite ; barres du
  graphe étiquetées (tranche + ml), cohérent avec le graphe existant de `HistoryView`.

### 3. Point d'entrée — `Wello/Wello/Views/HistoryView.swift` (modifié)

Sous `statsCard(conso)` dans `contenu`, ajouter une entrée « Analyses détaillées » :

- `entitlements.isUnlocked(.analytics)` vrai → `NavigationLink { AnalyticsView() } label: { … }` (carte
  cliquable cohérente avec les cartes jour).
- faux → `PremiumGateCard(bénéfice: "Analyses et tendances détaillées") { paywall = true }`
  (composant et `.sheet` paywall déjà présents dans `HistoryView`).

### 4. Inchangé

- Paywall : « Analyses et tendances » y figure déjà — aucun changement.
- `PremiumFeature.analytics` : déjà déclaré — aucun changement.
- `statsCard` gratuite (série + moyenne 7 j) : conservée telle quelle.
- StoreKit / `EntitlementStore` / `PreviewSupport.entitlements(_:)` : réutilisés tels quels.

## Données & fenêtres

- **Taux d'atteinte** : `objectifs` → `DailyTotal[]` (récent→ancien), `prefix(7)` et `prefix(30)`.
- **Tendance** : mêmes `DailyTotal[]`, `lastN: 7` et `lastN: 30`.
- **Meilleure série** : sur **tout** l'historique disponible (`totals`).
- **Répartition horaire** : logs des 30 derniers jours (`loggedAt >= startOfDay(now − 29 j)`).

Premium = historique illimité, donc ces fenêtres opèrent sur la totalité des données présentes.

## Cas limites

- 0 jour d'historique → `AnalyticsView` affiche un état vide global (réutilise le style `étatVide`
  de `HistoryView`).
- < 7 ou < 30 jours → `reachRate`/`averageConsumed` opèrent sur ce qui est disponible (le `prefix`
  borne sans erreur) ; libellés « 7 j / 30 j » conservés (la fenêtre est un *maximum*).
- Aucune prise d'eau sur 30 j → carte répartition en état vide, pas de graphe à 0.
- `goalML == 0` un jour donné → `DailyTotal.reached` est déjà `false` (garde existante).

## Tests (WelloKit, CLI)

Nouvelle suite / ajouts dans `WelloKitTests` :

- `reachRate` : liste vide → 0 ; 3/4 atteints → 0.75 ; tous atteints → 1.0.
- `bestStreak` : liste vide → 0 ; record au milieu (ex. `[✓✗✓✓✓✗✓]` → 3) ; tous atteints → n.
- `hydrationByPeriod` : renvoie toujours 5 tranches ordonnées ; somme correcte par tranche ;
  bornes (`DayPeriod.from(hour:)` : 6→matin, 11→midi, 13→midi, 14→aprèsMidi, 23→nuit, 0→nuit, 5→nuit).

## Vérification finale

1. `cd WelloKit && swift test` → vert (dont nouvelles fonctions stats).
2. Type-check iOS hors Xcode (commande complète du `CLAUDE.md`) → 0 erreur.
3. Previews Xcode (manuel) : `AnalyticsView` en `.plus` montre les 4 cartes ; `HistoryView`
   « Gratuit » montre la `PremiumGateCard` analytics, « Wello+ » montre le lien vers Analyses.
