# Widget iOS (Phase 2) — Design

> Spec de conception. Le plan d'implémentation détaillé suivra (skill `writing-plans`).

## Objectif

Donner à Wello des **widgets iOS** qui montrent la progression d'hydratation du jour et
permettent un **ajout rapide** sans ouvrir l'app, en réutilisant le store SwiftData local
existant. Première brique de la Phase 2 (le découpage services/calculateur a été conçu pour
l'accueillir sans refonte).

100 % local, mono-appareil, **pas de CloudKit** : le partage app↔widget passe par un **App Group**.

## Périmètre

**Dans le périmètre :**
- Widget d'accueil **petit** — anneau de progression, **affichage seul**, tap → app.
- Widget d'accueil **moyen** — en-tête valeurs + barre + **3 boutons d'ajout rapide** (App Intents,
  iOS 17), **interactif** (écrit une prise sans ouvrir l'app).
- Accessoire **écran verrouillé circulaire** — anneau teinté, **affichage seul**.

**Hors périmètre (YAGNI, ajoutable plus tard) :**
- Widget large ; accessoire rectangulaire/inline.
- Choix du type de boisson depuis le widget (eau uniquement, coefficient 1.0).
- Widget configurable (paramètres d'instance).
- watchOS / complication Watch.

## Décisions de conception

### Partage de données : store SwiftData partagé dans l'App Group (approche A)

L'app et l'extension widget ouvrent **le même** store SwiftData via une
`ModelConfiguration(groupContainer: .identifier("group.Life.Wello"))`.

- Le widget **lit** `DailyGoal` (objectif du jour) et somme les `HydrationLog.effectiveML` du jour.
- L'`AddWaterIntent` **insère** un `HydrationLog` dans le store partagé puis recharge les timelines.

Approche retenue car c'est la seule qui honore l'ajout rapide **sans ouvrir l'app** tout en
réutilisant le modèle existant (`effectiveML`, dédup, etc.) sans couche de synchro. Alternatives
écartées : snapshot lecture seule + file d'écriture (l'ajout n'est pas persisté tant que l'app
n'est pas rouverte → casse l'usage) ; widget lecture seule + deeplink (ouvre l'app à chaque ajout).

### Identité & cibles

- App Group : **`group.Life.Wello`** — entitlements de l'app **et** de l'extension.
- Extension widget : **WelloWidget**, bundle `Life.Wello.WelloWidget`.
- Les 3 `@Model` (`UserProfile`, `DailyGoal`, `HydrationLog`) restent définis dans l'app mais sont
  **ajoutés à la membership de la cible widget**. Ils ne migrent pas dans WelloKit : SwiftData
  n'est pas disponible pour `swift test` (compilation CLI), ce qui casserait les tests.
- L'extension lie aussi **WelloKit** (pour `effectiveHydrationML`, `DrinkType`, `WidgetProgress`).
- Fichier partagé **`WelloShared.swift`** (membership app + widget) : identifiant d'App Group +
  fabrique `ModelContainer` commune (une seule source de configuration du store).

### Migration du store (unique, idempotente)

Au démarrage, avant de construire le container : si le store de l'App Group **n'existe pas** et que
le store par défaut existe, copier `default.store` (+ `-wal`, `-shm`) vers le dossier de l'App
Group. Puis ouvrir **toujours** le container App Group.

- Préserve l'historique des utilisateurs existants après mise à jour.
- Idempotent : une fois le store App Group présent, la copie ne se reproduit jamais.

## Architecture & composants

### `WelloShared.swift` (app + widget)
- `enum WelloShared { static let appGroupID = "group.Life.Wello" }`
- Fabrique qui construit le `ModelContainer` (modèles + `ModelConfiguration` App Group), effectue
  la migration si nécessaire, et est utilisée par `WelloApp` comme par le widget.

### Lecture — `Provider` (widget)
- Ouvre le container partagé, lit le `DailyGoal` du jour (`totalML`) et somme les
  `HydrationLog.effectiveML` du jour → une `Entry { date, consomméML, objectifML, quickAdds }`.
- Reload policy `.after(~15 min)` (filet de sécurité ; l'app/intent rechargent à la demande).
- Si aucun `DailyGoal` du jour (sexe non renseigné / pas encore calculé) → entry « à configurer ».

### Calcul d'affichage — `WidgetProgress` (WelloKit, pur, testé CLI)
Type pur qui dérive de `(consomméML, objectifML)` :
- `fraction` bridée 0…1 (anneau), `pourcent` réel (peut dépasser 100, peut être 0 si négatif),
- libellés formatés « 1,4 / 2,3 L » et « 62 % ».
- Gère consommé négatif (coefficients diurétiques) et consommé > objectif.

### Vues widget
- **Petit** : anneau (style A) — `%` au centre, valeurs dessous.
- **Moyen** : en-tête (valeurs + %), barre de progression, 3 boutons `Button(intent: AddWaterIntent(amountML:))`.
- **accessoryCircular** : `Gauge`/anneau en rendu teinté (écran verrouillé), lecture seule.

### Écriture — `AddWaterIntent: AppIntent`
- Paramètre `amountML`. `perform()` : ouvre le container partagé, insère
  `HydrationLog(amountML:, source: "app", drinkType: "water", coefficient: 1.0)`, sauvegarde,
  puis `WidgetCenter.shared.reloadAllTimelines()`.
- Montants des boutons = `UserProfile.quickAdds` lus dans le `Provider`.

### Rafraîchissement déclenché par l'app
`HydrationStore` appelle `WidgetCenter.shared.reloadAllTimelines()` après chaque changement du
consommé/objectif (ajout, suppression, `refreshToday`).

## Flux de données

```
[App] saisie/import ──┐
                      ├─►  Store SwiftData partagé (App Group)  ◄──┐
[Widget AddWaterIntent]──────────── insert HydrationLog ──────────┘
                      │
   reloadAllTimelines │ (app après changement ; intent après insert)
                      ▼
            [Widget Provider] lit DailyGoal + Σ effectiveML
                      ▼
        WidgetProgress → vues (petit / moyen / accessoryCircular)
```

## Cas limites & erreurs

- **Sexe non renseigné / pas de `DailyGoal`** : état « À configurer » (anneau vide, « Ouvre Wello »).
- **Consommé négatif ou > objectif** : `%` réel affiché, anneau bridé 0–100 %.
- **Écran verrouillé** : accessoire teinté, sans couleur ni bouton.
- **Permissions refusées** (Santé/localisation/notifs) : inchangé — le widget reflète l'état du
  store local ; l'app reste pleinement utilisable en saisie manuelle.

## Stratégie de test

- **CLI (`swift test`)** : `WidgetProgress` (fraction bridée, pourcent réel, clamp, formatage,
  cas négatif et dépassement).
- **Type-check iOS hors Xcode** : code app modifié (fabrique container partagé, hooks
  `WidgetCenter`). Le code de l'extension widget (WidgetKit/AppIntents) n'est pas inclus dans les
  globs de type-check actuels — validé en preview Xcode.
- **Manuel Xcode** : création de la cible WelloWidget, entitlements App Group (×2), preview des
  3 familles, test de la migration (ancienne version → MAJ → historique conservé), ajout rapide
  depuis le widget moyen (prise persistée, app la voit au `foreground`).

## Étapes Xcode / appareil (manuelles, hors CLI)

- Créer la cible **WelloWidget** (Widget Extension) ; y inclure `WelloWidget.swift`,
  les vues, l'intent, `WelloShared.swift`, et la membership des 3 `@Model`.
- Lier **WelloKit** à la cible widget.
- Capability **App Group `group.Life.Wello`** sur l'app et sur l'extension.
- Lancer une fois l'ancienne version (store par défaut peuplé) puis la nouvelle pour valider la
  migration.
