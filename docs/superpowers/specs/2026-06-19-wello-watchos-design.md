# App watchOS (Phase 2) — Design

> Spec de conception. Le plan d'implémentation détaillé suit (skill `writing-plans`).
> Périmètre : **app Watch seule** (la complication de cadran viendra dans un second temps).

## Objectif

Donner à Wello une **app Apple Watch autonome** qui montre la progression d'hydratation du jour
(jauge + objectif) et permet un **ajout rapide d'eau au poignet**, même iPhone absent. Deuxième
brique de la Phase 2 après le widget iOS. Réutilise la logique pure de `WelloKit` (calcul
d'objectif, affichage de progression) et reste **100 % local, sans CloudKit**.

## Contrainte structurante : deux appareils, pas de store partagé

Le widget iOS partage les données avec l'app via un **App Group** parce qu'ils tournent sur le
**même appareil**. L'iPhone et la Watch sont **deux appareils distincts** : un App Group ne les
relie pas, et le README exclut CloudKit par principe (app « mono-appareil »). La synchronisation
iPhone↔Watch passe donc par :

- **WatchConnectivity (`WCSession`)** — canal applicatif direct, hors-ligne géré (files d'attente).
- **HealthKit** — la Watch *lit* l'énergie active pour recalculer l'objectif au poignet ;
  l'écriture de l'eau dans Santé.app reste **côté iPhone** (un seul écrivain → pas de double compte).

## Périmètre

**Dans le périmètre :**
- App Watch **autonome** : jauge de progression (anneau + %, valeurs en L), **3 boutons d'ajout
  rapide** (montants repris du profil iPhone), annulation de la dernière prise locale non encore
  synchronisée.
- **Fonctionne hors-ligne** : la jauge bouge immédiatement à chaque tap (affichage optimiste) ;
  les prises sont mises en file et envoyées à l'iPhone à la reconnexion (`transferUserInfo`,
  livraison garantie).
- **Recalcul autonome de l'objectif** : une fois le profil reçu au moins une fois, la Watch peut
  faire **monter la part « activité »** de l'objectif à partir de sa propre énergie active
  HealthKit, même iPhone absent (utile en séance). Elle ne recalcule **pas** la météo (elle fait
  confiance à l'objectif poussé par l'iPhone pour ce terme).
- **Mirroir iPhone→Watch** : l'iPhone pousse objectif + consommé + montants rapides + profil
  minimal à chaque changement (`updateApplicationContext`, dernier-état-gagne, coalescé).

**Hors périmètre (YAGNI, ajoutable plus tard) :**
- **Complication de cadran** (anneau sur le cadran) — chantier suivant ; le découpage prévu ici
  l'accueille sans refonte (réutilise `WidgetProgress` + le même mirroir).
- Choix du type de boisson au poignet (eau uniquement, coefficient 1.0).
- Écriture HealthKit **depuis la Watch** (l'iPhone reste l'unique écrivain en v1).
- Annulation au poignet d'une prise **déjà synchronisée** (se fait sur l'iPhone).
- Rappels/notifications sur la Watch, réglages du profil au poignet.

## Décisions de conception

### Sync intakes (Watch→iPhone) = WatchConnectivity, source de vérité

Chaque tap au poignet crée une `PriseWatch { id: UUID, amountML, loggedAt }` :
1. ajoutée localement (affichage optimiste immédiat, persistée pour survivre au relaunch) ;
2. envoyée à l'iPhone via `session.transferUserInfo(...)` — **file FIFO à livraison garantie**,
   même iPhone injoignable au moment du tap.

À réception, l'iPhone insère un `HydrationLog(source: "watch")`, écrit l'eau dans Santé.app
(**unique écrivain HealthKit**), replanifie les rappels, recharge les widgets, puis **repousse un
snapshot** dont le champ `acquittés` contient désormais l'`id` de cette prise. La Watch, voyant son
`id` acquitté, **purge** la prise locale correspondante → l'objectif/consommé affiché provient alors
du total autoritaire de l'iPhone, **sans double comptage**.

**Pourquoi pas HealthKit pour ce sens ?** Si la Watch écrivait l'eau dans HealthKit, l'iPhone
l'importerait (`prisesEauExternes`) en plus de la recevoir par `WCSession` → **double compte** (la
source HealthKit de l'app Watch diffère de `HKSource.default()`, donc l'import ne l'exclurait pas).
WatchConnectivity porte un `UUID` → déduplication et acquittement exacts. HealthKit garde son rôle
**en lecture** sur la Watch (énergie active pour le recalcul autonome).

### Mirroir iPhone→Watch = `updateApplicationContext`

L'iPhone pousse un `WatchSyncSnapshot` (objectif, consommé autoritaire, montants rapides, profil
minimal, `acquittés`, horodatage) après **chaque** mutation (ajout, suppression, `refreshToday`).
`updateApplicationContext` est **coalescé** (dernier état gagne) et **persistant** (re-livré au
réveil de la Watch) → idéal pour un mirroir d'état. La Watch applique le snapshot, purge ses prises
acquittées et redessine la jauge.

### Réconciliation du consommé (cœur testable, dans WelloKit)

L'état affiché à la Watch est dérivé **purement** d'un snapshot + d'une file de prises locales :

```
consomméAffiché = snapshot.consomméML  +  Σ amountML des prises locales dont l'id ∉ snapshot.acquittés
```

- **En ligne** : l'iPhone acquitte vite → les prises locales se vident → on affiche le total iPhone.
- **Hors-ligne** : `acquittés` n'évolue plus → la Watch continue d'ajouter ses taps au dernier
  consommé connu → la jauge bouge. À la reconnexion, l'iPhone ingère, acquitte, la Watch purge.

Aucun double comptage, aucune divergence persistante, aucun CloudKit. Cette réconciliation +
le codec dictionnaire (`[String: Any]` plist-safe pour `WCSession`) vivent dans **WelloKit** et
sont **testés en CLI** (`swift test`).

### « Autonome » sans second store SwiftData

L'autonomie demandée (jauge + log + recalcul hors-ligne) est réalisée par un **état persisté léger**
(`ÉtatHydratationWatch` + file de prises en `UserDefaults`/`@AppStorage`), **pas** par une seconde
base SwiftData dupliquée sur la Watch. Raison : deux stores SwiftData indépendants (un par appareil)
qui sommeraient chacun leurs logs **se double-compteraient** face au total poussé par l'iPhone, et
imposeraient une couche de réconciliation d'ensembles bien plus lourde que le modèle « snapshot
autoritaire + file optimiste acquittée » retenu ici. Le résultat est identique du point de vue
utilisateur (montre pleinement utilisable sans téléphone), pour beaucoup moins de surface de bug.

### Recalcul autonome de l'objectif (WelloKit au poignet)

Quand la Watch a déjà reçu un snapshot (donc le profil minimal : sexe, état physio, rénal, réglage
avancé) mais que l'iPhone est absent, elle peut **recalculer** via `HydrationCalculator` :

```
objectifAffiché = max( snapshot.objectifML ,  HydrationCalculator(profil, énergieActiveWatch, weather: nil) )
```

On prend le **maximum** : la météo (connue seulement de l'iPhone) reste intégrée via l'objectif
poussé, et la part « activité » peut **monter** au poignet pendant une séance. Les plafonds de
sécurité de `HydrationCalculator` (activité ≤ 1000, total ≤ 4000) s'appliquent naturellement. Sans
snapshot (Watch jamais synchronisée), l'objectif est « à configurer » (on n'invente pas de base).

### Identité & cibles

- Cible **WelloWatch** (watchOS App), bundle `Life.Wello.watchkitapp`, déploiement watchOS 10+.
- Lie **WelloKit** (calcul + réconciliation + `WidgetProgress`).
- **HealthKit** sur la cible Watch (lecture énergie active) : capability + `NSHealthShareUsageDescription`.
- `WCSession` ne demande **aucune** capability ; juste le code des deux côtés.
- Côté iPhone : ajout d'un `WatchConnectivityService` (cible app) + champ `watchUUID` sur
  `HydrationLog` (déduplication des prises Watch).

## Architecture & composants

### WelloKit (pur, testé CLI)

- **`PriseWatch`** — `{ id: UUID, amountML: Int, loggedAt: Date }`, `Codable` + codec dictionnaire
  (`dictionnaire()` / `init?(dictionnaire:)`) pour `transferUserInfo`.
- **`WatchSyncSnapshot`** — `objectifML, consomméML, quickAdds, configuré, sexeRaw?, etatPhysioRaw?,
  renalBonusML, activitySensitivity, weatherSensitivity, manualAdjustmentML, acquittés: [UUID],
  générémLe: Date`. `Codable` + codec dictionnaire plist-safe (UUID→String, Date→Double).
- **`ÉtatHydratationWatch`** — réducteur pur :
  - état : `snapshot?`, `prisesLocales: [PriseWatch]`, `énergieActiveKcal: Double`.
  - dérivés : `prisesEnAttente` (id ∉ acquittés), `consomméML`, `objectifML` (max poussé/recalculé),
    `configuré`, `quickAdds`, `progress: WidgetProgress`.
  - mutations : `ajouterPrise(_:)`, `appliquer(_ snapshot:)` (purge les acquittées),
    `annulerDernièreEnAttente() -> PriseWatch?`, `mettreÀJourÉnergie(_:)`.
- Réutilise **`WidgetProgress`** (fraction/%/libellés) et **`HydrationCalculator`** existants.

### Cible iPhone (app)

- **`HydrationLog.watchUUID: UUID?`** (défaut inline `nil` → migration légère SwiftData) : marque
  les prises issues de la Watch, pour la déduplication et le calcul des `acquittés`.
- **`WatchSyncing`** (protocole) + **`WatchConnectivityService`** (réel, `WCSessionDelegate`) +
  **mock** : `func pousser(_ snapshot: WatchSyncSnapshot)`. Reçoit les prises distantes via une
  closure injectée à l'app (`onPriseDistante`).
- **`HydrationStore`** : dépendance `watchSync` injectée ; nouvelles méthodes
  `snapshotWatch() -> WatchSyncSnapshot` (objectif/consommé/quickAdds/profil/`acquittés` du jour) et
  `enregistrerPriseDistante(_ p: PriseWatch)` (dédup par `watchUUID`, insert `source:"watch"`,
  `écrireEau`, replanif, recharge widgets) ; appel `pousserSnapshotWatch()` après chaque mutation
  (comme `rechargerWidgets()`).
- **`WelloApp`** : crée le service, l'injecte au store, et branche `onPriseDistante` →
  `store.enregistrerPriseDistante`.

### Cible Watch (watchOS)

- **`WelloWatchApp`** (`@main`) : scène unique, injecte un `WatchStore`.
- **`WatchStore`** (`@MainActor @Observable`) : détient `ÉtatHydratationWatch`, persiste la file de
  prises locales (`UserDefaults`), expose `consommé/objectif/progress/quickAdds`, et les actions
  `ajouter(ml:)` (optimiste + envoi) / `annulerDernière()`.
- **`WatchConnectivityClient`** (`WCSessionDelegate`) : active la session, `envoyer(_ prise:)` via
  `transferUserInfo`, reçoit le snapshot via `didReceiveApplicationContext` → `WatchStore.appliquer`.
- **`HealthKitWatchService`** : lecture de l'énergie active du jour (pour le recalcul). Dégrade à 0
  si refusé/indisponible.
- **Vues** : `WatchMainView` (anneau `Ring` + % + « x,y / z,t L » + 3 boutons `+ml` + annuler).
  Teintes dupliquées (découplage du thème app, comme le widget).

## Flux de données

```
                      WCSession.transferUserInfo({id,ml,loggedAt})  (file garantie)
[Watch] tap ──► ÉtatHydratationWatch.ajouterPrise (optimiste) ───────────────────────► [iPhone]
   ▲                                                                                       │
   │ jauge = snapshot.consommé + Σ prises non acquittées                                   │ enregistrerPriseDistante
   │                                                                                       │  (HydrationLog source:"watch",
   │   updateApplicationContext(WatchSyncSnapshot{objectif,consommé,acquittés,profil,...})  │   écrireEau, replanif)
   └───────────────────────────────────────────────────────────────────────────────────  ◄┘  pousserSnapshotWatch()
                                                                                            (après TOUTE mutation iPhone)
[Watch] HealthKit énergie active ──► objectif = max(poussé, HydrationCalculator(profil,énergie,nil))
```

## Cas limites & erreurs

- **Watch jamais synchronisée** (aucun snapshot) : état « Ouvre Wello sur l'iPhone » (anneau vide).
- **iPhone hors de portée** : taps mis en file (`transferUserInfo`), jauge optimiste ; recalcul de
  l'objectif possible via l'énergie active locale ; tout se réconcilie à la reconnexion.
- **HealthKit refusé sur la Watch** : énergie = 0 → pas de bump d'activité, objectif = celui poussé.
  L'app reste pleinement utilisable (ajout manuel).
- **Double compte** : exclu par construction — un seul écrivain HealthKit (iPhone) ; prises Watch
  dédupliquées par `watchUUID` ; consommé local borné par l'ensemble `acquittés`.
- **Consommé négatif / dépassement** : géré par `WidgetProgress` (anneau bridé 0–100 %, % réel).
- **Annulation au poignet** : ne retire qu'une prise **locale non acquittée** ; une prise déjà
  synchronisée se supprime sur l'iPhone (hors périmètre v1, documenté).

## Stratégie de test

- **CLI (`swift test`)** : `PriseWatch` et `WatchSyncSnapshot` (round-trip codec dictionnaire,
  types plist-safe, champs optionnels) ; `ÉtatHydratationWatch` (consommé = autoritaire + non
  acquittés ; purge à l'application d'un snapshot ; recalcul objectif = max poussé/local ; annulation
  d'une prise en attente ; cas non configuré / hors-ligne).
- **Type-check iOS hors Xcode** : code app modifié (modèle `watchUUID`, `WatchSyncing`+mock,
  `WatchConnectivityService`, hooks `HydrationStore`, `WelloApp`). `WatchConnectivity` est dans le
  SDK iOS → type-check possible. Le code **watchOS** (cible Watch) n'est pas dans les globs CLI :
  fourni complet, validé en **preview/au simulateur Xcode**.
- **Manuel Xcode** : création de la cible Watch, capability HealthKit + usage string, preview de
  `WatchMainView` ; sur appareils/simulateurs jumelés : tap au poignet → prise visible sur l'iPhone
  et dans Santé.app ; mode avion sur l'iPhone → la jauge Watch bouge quand même, puis se réconcilie ;
  une prise saisie sur l'iPhone met à jour la jauge Watch.

## Étapes Xcode / appareil (manuelles, hors CLI)

- Créer la cible **WelloWatch** (watchOS App) ; y inclure les sources `Wello/WelloWatch/` ;
  déploiement **watchOS 10+**.
- Lier **WelloKit** à la cible Watch.
- Capability **HealthKit** sur la cible Watch + `NSHealthShareUsageDescription` dans son Info.plist
  (lecture énergie active).
- Ajouter `WatchConnectivityService.swift` à la cible **app iPhone** (framework `WatchConnectivity`,
  déjà dans le SDK — aucune capability).
- Jumeler iPhone + Watch (simulateurs jumelés ou appareils) pour valider le flux complet.
</content>
</invoke>
