# CLAUDE.md — Wello

App iOS personnelle de suivi d'hydratation, 100 % locale, mono-appareil.
**Le `README.md` fait foi** pour l'architecture, la logique de calcul, les permissions et le
périmètre Phase 1/2 — le lire plutôt que ré-explorer.

## Carte du projet

- `WelloKit/` — Swift Package, **logique métier pure et testable en CLI** (`HydrationCalculator`,
  `BiologicalSex`, modèles de calcul). Toute logique critique va ici.
- `Wello/Wello/` — app Xcode (SwiftUI/SwiftData/HealthKit) : `App/`, `Models/`, `Services/`,
  `Views/`. Pattern « MV » (pas de ViewModels), services derrière protocoles + mocks.
- `Wello/WelloWidget/` — extension WidgetKit (Phase 2) : `Provider` lisant le store partagé,
  vues des familles, `AddWaterIntent`. Partage le store via App Group `group.Life.Wello`.
- `Wello/WelloWatch Watch App/` — app watchOS (Phase 2) : `WatchStore` + vues, sync via WatchConnectivity
  (mirroir iPhone→Watch + prises Watch→iPhone) et HealthKit en lecture. Pas de store partagé (deux
  appareils, pas de CloudKit) ; réconciliation pure dans WelloKit (`ÉtatHydratationWatch`).
- `docs/superpowers/` — spec design + plan d'implémentation.

## Vérifier le code (sans build Xcode pilotable en CLI)

L'utilisateur crée le projet/targets et compile/run dans Xcode lui-même ; Claude fournit les
sources. Pour prouver que le code est valide :

```bash
# 1. Logique pure — tests réels
cd WelloKit && swift test

# 2. App iOS — type-check hors Xcode (depuis la racine)
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

0 erreur = code compilable. Les macros SwiftData/Observation/`#Predicate` se résolvent via le SDK.
Le flag `MemberImportVisibility` reproduit le contrôle d'Xcode (Swift 6) : tout fichier qui
utilise un membre d'un type `WelloKit` (ex. `.unlimitedHistory`, `.free`) doit **importer
`WelloKit` explicitement**, même si le type est accessible transitivement. Sans ce flag, le
type-check CLI passe alors qu'Xcode échoue.

## Étapes Xcode manuelles (non automatisables ici)

Lier le package local `WelloKit` au target, capability HealthKit, et clés Info.plist :
`NSHealthShareUsageDescription`, `NSHealthUpdateUsageDescription`,
`NSLocationWhenInUseUsageDescription`. Détails dans le README.
Cible WidgetExtension `WelloWidget` : membership des 3 `@Model` + `WelloShared.swift`, lien WelloKit,
capability App Group `group.Life.Wello` sur l'app ET l'extension.
Cible watchOS `WelloWatch` : sources dans le **dossier synchronisé** `Wello/WelloWatch Watch App/`
(c'est CE dossier que la cible compile, pas `Wello/WelloWatch/` — ne pas recréer de doublon), lien WelloKit, capability
HealthKit + `NSHealthShareUsageDescription` (lecture énergie active). `WatchConnectivityService.swift`
appartient à la cible app iPhone. Pas de capability WatchConnectivity (SDK). watchOS 10+.
Thèmes (Wello+) : les **couleurs** marchent sans étape manuelle ; les **icônes alternatives**
exigent d'ajouter les assets `AppIcon-Aurore/-Menthe/-Crepuscule` + de déclarer
`CFBundleIcons`/`CFBundleAlternateIcons` (via `INFOPLIST_KEY_*`). Tant qu'ils manquent,
`ThemeStore.appliquerIcône` échoue silencieusement. Voir spec `2026-06-18-wello-themes-design.md`.

## Conventions

- Tous les refus de permission (HealthKit, localisation, notifications) doivent rester gérés :
  l'app reste pleinement utilisable en saisie manuelle.
- Objectif d'hydratation plafonné à 4000 ml, jamais sous le plancher médical.
- Pas de CloudKit : partage app ↔ widget (Phase 2) via App Group.
