# Export CSV de l'historique (Wello+) — Design

**Statut :** livré.
**Date :** 2026-06-18.

## Problème

Le paywall annonçait « Export CSV / PDF » et `PremiumFeature.export` existe, sans implémentation.
On vend une feature absente.

## Décision

Livrer l'**export CSV** de l'historique, réservé à Wello+. Deux fichiers complémentaires :
**détail par prise** (données brutes) et **résumé par jour** (consommé vs objectif). Le PDF est
**retiré du périmètre** (et de la promesse paywall) : le CSV couvre le besoin réel (analyse dans
Numbers/Excel) sans le coût de mise en page non testable d'un PDF.

## Périmètre

### Inclus
1. `HydrationExport` (WelloKit, pur) : sérialisation CSV déterministe, testée en CLI.
2. `HydrationExporter` (app) : mappe les `@Model` → structs d'export → fichiers temporaires.
3. `ShareSheet` (pont `UIActivityViewController`) + bouton « Exporter » dans `HistoryView`.
4. Gating : non débloqué → `PaywallView`. Paywall reformulé « Export CSV de l'historique ».

### Exclu
- PDF (retiré). Filtrage par plage de dates à l'export (on exporte tout l'historique : déjà
  premium = illimité). Export programmé / partage automatique.

## Architecture

### WelloKit — `HydrationExport.swift` (pur)

```swift
public struct ExportLogRow   { loggedAt, drinkLabel, volumeML, coefficient, effectiveML, source }
public struct ExportDaySummary { day, consumedML, goalML; var reached }
public enum HydrationExport {
    static func detailCSV(_ rows: [ExportLogRow], timeZone: TimeZone = .current) -> String
    static func summaryCSV(_ days: [ExportDaySummary], timeZone: TimeZone = .current) -> String
}
```
- Dates : locale POSIX, horodatage local `yyyy-MM-dd'T'HH:mm:ss` (détail) / `yyyy-MM-dd` (résumé).
- Coefficient : `%.2f` point décimal (indépendant de la locale).
- Séparateur virgule, fins de ligne `\r\n`, échappement RFC 4180 (guillemets si `,`/`"`/saut).

### App — `HydrationExporter.swift`

- `detailFile(logs:)` : prises triées récentes d'abord → `Wello-prises-AAAA-MM-JJ.csv`.
- `summaryFile(logs:goals:)` : consommé/jour agrégé (borné ≥ 0 via `clampedDayTotal`) joint aux
  `DailyGoal` → `Wello-jours-AAAA-MM-JJ.csv`.
- Écriture UTF-8 **avec BOM** (accents corrects sous Excel) dans `temporaryDirectory`.

### UI — `HistoryView`

Bouton barre (`square.and.arrow.up`), masqué si l'historique est vide. Tap : si `.export`
débloqué → génère les 2 fichiers et présente `ShareSheet([prises, jours])` ; sinon paywall.
Erreur d'écriture → alerte. Exporte **tout** l'historique (cohérent avec premium = illimité).

## Cas limites

- Historique vide → pas de bouton.
- Objectif nul d'un jour → `Atteint = non` (pas de division par zéro).
- Libellés à virgule/guillemets (improbable mais géré) → échappés RFC 4180.

## Vérification

1. `cd WelloKit && swift test` → vert (suite `HydrationExport`).
2. Type-check iOS app + widget → 0 erreur.
3. Manuel : en Wello+, bouton Exporter → feuille de partage avec 2 CSV ouvrables dans Numbers ;
   en gratuit → paywall.
