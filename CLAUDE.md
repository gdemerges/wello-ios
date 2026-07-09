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

**CI** : `.github/workflows/ci.yml` (macos-15) rejoue exactement ces deux vérifications à chaque
push/PR (`swift test` + type-check). L'orchestrateur `HydrationStore` (cible app, SwiftData) n'a
pas de tests d'intégration : ils exigeraient une cible *Unit Testing Bundle* Xcode (non pilotable
en CLI). La logique délicate est donc extraite dans WelloKit et testée là (calcul, rappels,
dédup/pierres tombales d'import, bilan, insights…).

## Étapes Xcode manuelles (non automatisables ici)

Lier le package local `WelloKit` au target, capability HealthKit, et clés Info.plist :
`NSHealthShareUsageDescription`, `NSHealthUpdateUsageDescription`,
`NSLocationWhenInUseUsageDescription`. Détails dans le README.
Cible WidgetExtension `WelloWidget` : membership des 3 `@Model` + `WelloShared.swift`, lien WelloKit,
capability App Group `group.Life.Wello` sur l'app ET l'extension.
Surfaces d'entrée (Siri / Spotlight / Bouton Action / Control Widget) : `AddWaterIntent.swift` a été
déplacé de `WelloWidget/` vers `App/` (intent partagé) — il doit être membre des DEUX cibles (app +
`WelloWidget`), comme `HydrationActivityAttributes.swift`. `WaterAppShortcuts.swift` (dossier `App/`,
cible **app** seule) déclare l'`AppShortcutsProvider` → Siri/Spotlight/Bouton Action, préréglé 250 ml.
`WelloControl.swift` (dossier `WelloWidget/`, cible widget) = Control Widget iOS 18 (Centre de contrôle /
écran verrouillé), déjà ajouté à `WelloWidgetBundle` (gardé `if #available(iOS 18)`). Aucune capability
dédiée ; App Shortcuts s'indexe après le 1ᵉʳ lancement de l'app.
Live Activity (progression du jour, écran verrouillé + Dynamic Island) : clé Info.plist
`NSSupportsLiveActivities = YES` sur l'app iPhone ; `HydrationActivityAttributes.swift`
(dossier `App/`) doit être membre des DEUX cibles (app + `WelloWidget`) ; `HydrationLiveActivity.swift`
appartient à `WelloWidget` (déjà déclaré dans `WelloWidgetBundle`). L'app démarre/actualise
l'activité via `LiveActivityManager` (cible app) ; inerte si l'utilisateur désactive les Live
Activities. Aucune capability dédiée.
Monétisation : deux produits StoreKit à créer dans **App Store Connect** — abonnement
auto-renouvelable annuel `com.wello.plus.annual` (4,99 €, essai gratuit 7 j) dans un groupe
d'abonnement, et non-consommable `com.wello.plus.lifetime` (12,99 €). `Wello.storekit` reflète
déjà les deux pour le test local. Wello+ est accordé si l'un OU l'autre est actif.
Cible watchOS `WelloWatch` : sources dans le **dossier synchronisé** `Wello/WelloWatch Watch App/`
(c'est CE dossier que la cible compile, pas `Wello/WelloWatch/` — ne pas recréer de doublon), lien WelloKit, capability
HealthKit + `NSHealthShareUsageDescription` (lecture énergie active). `WatchConnectivityService.swift`
appartient à la cible app iPhone. Pas de capability WatchConnectivity (SDK). watchOS 10+.
Cible complication `WelloWatchWidget` (Watch Widget Extension) : sources dans `Wello/WelloWatchWidget/`,
lien WelloKit ; `WelloWatchShared.swift` (dossier `WelloWatch Watch App/`) doit être membre des DEUX
cibles (app Watch + widget) ; capability App Group `group.Life.Wello` sur l'app Watch ET le widget
(conteneur local à la montre, distinct de celui de l'iPhone). Familles de cadran circular/corner/
inline/rectangular.
Thèmes (Wello+) : les **couleurs** marchent sans étape manuelle ; les **icônes alternatives**
exigent d'ajouter les assets `AppIcon-Aurore/-Menthe/-Crepuscule` + de déclarer
`CFBundleIcons`/`CFBundleAlternateIcons` (via `INFOPLIST_KEY_*`). Tant qu'ils manquent,
`ThemeStore.appliquerIcône` échoue silencieusement. Voir spec `2026-06-18-wello-themes-design.md`.
Localisation : langue de base **fr** + **7 langues** traduites (en, es, de, it, pt-BR, ja, zh-Hans).
`knownRegions` (pbxproj) contient les 8 régions. Étape manuelle : ajouter `Wello/Wello/Localizable.xcstrings`
au target app (Target Membership), puis un build extrait automatiquement les nouvelles clés manquantes.
Le catalogue (153 clés) est **entièrement traduit** dans les 7 langues (152 clés × 7 ; la clé vide `""`
est ignorée). Les littéraux SwiftUI sont des `LocalizedStringKey` (aucun `String(localized:)` requis).
Une clé sans traduction retombe sur le français (fallback sûr). Après ajout de clés, penser à compléter
les 7 langues (une clé partiellement traduite retombe sur le fr pour les langues manquantes).

## Conventions

- Tous les refus de permission (HealthKit, localisation, notifications) doivent rester gérés :
  l'app reste pleinement utilisable en saisie manuelle.
- Objectif d'hydratation plafonné à 4000 ml, jamais sous le plancher médical.
- Pas de CloudKit : partage app ↔ widget (Phase 2) via App Group.
