# Wello — Rappels adaptatifs (« Wello+ ») — Design

**Date :** 2026-06-08
**Statut :** Validé pour implémentation
**Pré-requis :** Mode premium livré (`2026-06-04-wello-premium-design.md`) — infra StoreKit,
`EntitlementStore`, gating réutilisable, `PremiumFeature.adaptiveReminders` déjà déclaré.

## Contexte & objectif

Les rappels actuels sont **fixes** : `NotificationService` pose deux rappels « retard » à 14h
et 17h, plus un rappel post-séance et un snooze. Ils ignorent la consommation réelle et les
habitudes de l'utilisateur (la méthode `planifierRappels(objectifML:consomméML:)` reçoit déjà
ces valeurs mais ne s'en sert pas).

Ce spec livre la feature premium **« Rappels adaptatifs »** (`PremiumFeature.adaptiveReminders`) :
des rappels qui **apprennent les trous d'hydratation habituels** de l'utilisateur et rappellent
**en préventif, juste avant** un trou prédit. 100 % local, mono-appareil, aucun backend.

**Palier :** `free` conserve les rappels fixes existants (14h/17h) ; `plus` débloque l'adaptatif.

## Décisions validées en brainstorming

- **Signal = apprentissage des habitudes**, et plus précisément la détection des **trous
  récurrents (« dry spells »)** : on rappelle avant la période où l'utilisateur décroche
  habituellement. Préventif, pas réactif.
- **Tout automatique, juste on/off.** Aucun réglage manuel de fenêtre/fréquence/sensibilité.
- **Fenêtre d'éveil** déduite, dans l'ordre :
  1. **Sommeil HealthKit** (`sleepAnalysis`, best-effort, nouvelle lecture).
  2. **Historique** des prises (percentiles 1ʳᵉ / dernière prise).
  3. **Défaut 7h–21h**.
  Les réveils de l'app Horloge ne sont **pas accessibles** aux apps tierces (pas d'API publique).
- **Architecture A** : toute la logique délicate est **pure dans `WelloKit`** (testable en CLI) ;
  la couche iOS ne fait que de la plomberie. Pas de `BGTaskScheduler`.

## Architecture

Coule dans les patterns existants : logique pure dans `WelloKit`, service derrière protocole +
mock, orchestration dans le store `@Observable`, gating via `Entitlements`.

### Logique pure — `WelloKit/Sources/WelloKit/`

**`struct AdaptiveReminderPlanner` (pur, `Sendable`).**

Détection des trous habituels :

1. Fenêtre d'apprentissage : **14 derniers jours** glissants de prises (constante `joursHistoire`).
2. Pour chaque jour, calcul des **écarts entre prises consécutives** dans la fenêtre d'éveil,
   bords inclus (réveil → 1ʳᵉ prise, dernière prise → coucher).
3. Tout écart > **`minGap` = 2 h** (constante) est un « trou » ce jour-là ; on retient son
   **heure de début** (minutes depuis minuit).
4. **Regroupement** des débuts de trous par créneau (~1 h). Un créneau présent sur
   **≥ `seuilRécurrence` = 40 % des jours** = un **trou habituel** à cette heure.
5. Pour aujourd'hui : un rappel est posé **~15 min avant** (`leadTime`) chaque début de trou
   habituel ; filtré aux heures **strictement futures** (> `now`) ; **espacé ≥ 90 min**
   (`espacementMin`) ; **plafonné à 6/jour** (`plafondParJour`) ; **supprimé si l'objectif du
   jour est déjà atteint**.

Signature (indicative) :

```swift
func planRappels(historique: [JourDePrises], fenêtre: FenêtreÉveil,
                 now: Date, objectifAtteint: Bool) -> [Date]
```

où `JourDePrises` porte les minutes-depuis-minuit des prises d'un jour, et `FenêtreÉveil` porte
`réveilMin` / `coucherMin`. Déterministe → testable en `swift test`.

**Dérivation de la fenêtre d'éveil (fonctions pures) :**

- Depuis échantillons sommeil : fin du dernier `asleep` → réveil ; coucher **médian** sur les
  jours disponibles → fin de fenêtre.
- Repli historique : réveil ≈ **15ᵉ percentile** des 1ʳᵉˢ prises ; coucher ≈ **85ᵉ percentile**
  des dernières prises ; clampés à des bornes raisonnables.
- Repli ultime : **7h–21h**.

**Cold-start :** < **7 jours** (`minJoursPourAdaptatif`) de données → le planner signale
l'insuffisance ; l'app retombe sur les **rappels fixes** (14h/17h), même en `plus`.

> Les constantes (`minGap`, `seuilRécurrence`, `leadTime`, `espacementMin`, `plafondParJour`,
> `joursHistoire`, `minJoursPourAdaptatif`) sont nommées et documentées pour ajustement ultérieur.

### Couche app — `Wello/Wello/Services/`

- **`protocol SleepWindowProviding: Sendable`** : `func fenêtreÉveil() async -> FenêtreÉveil?`
  lit `HKCategoryType(.sleepAnalysis)` (best-effort) et renvoie une fenêtre, ou `nil`
  (refus/vide → replis de la logique pure). Implémentation réelle `HealthKitSleepWindow`
  (ou extension du service HealthKit existant) + **`MockSleepWindow`** dans `Mocks.swift`.
  Ajout du type sommeil au set de lecture HealthKit (**code** ; `NSHealthShareUsageDescription`
  déjà présent → **aucune nouvelle clé Info.plist ni capability**).
- **`NotificationServicing`** : on conserve `planifierRappels` (fixe, inchangé) et on ajoute
  **`func planifierRappelsAdaptatifs(auxHeures: [Date]) async`**. Identifiants `wello.adaptif.0…n`
  pour purge/replanification.
- **`HydrationStore`** orchestre, dans son flux de replanification existant
  (`refreshToday` / après chaque `log`) :
  1. `!remindersEnabled` → `annulerTout`, fin.
  2. `requestAuthorization` (existant).
  3. Selon `entitlements.isUnlocked(.adaptiveReminders)` :
     - `free` **ou** cold-start → `planifierRappels` (fixe, existant).
     - `plus` → récupère l'historique SwiftData (déjà accessible au store), lit
       `sleepWindow.fenêtreÉveil()` (replis sinon), appelle `AdaptiveReminderPlanner`, passe les
       heures à `planifierRappelsAdaptatifs`.
  4. Recalcul **à chaque refresh et chaque log** : purge `wello.adaptif.*` puis repose → gère
     « je viens de boire ».
  La lecture de l'entitlement est **injectée dans le store** (référence `EntitlementStore` ou
  closure de lecture), comme les autres dépendances.

### Gating — `WelloKit`

`Entitlements.isUnlocked(.adaptiveReminders)` (table existante : `free` verrouille, `plus`
déverrouille). Aucune modification de l'infra premium.

## UX & réglages

Section « Rappels » du Profil — le toggle `remindersEnabled` reste. Sous-titre d'état contextuel :

- `plus` + actif : « Rappels intelligents — basés sur tes habitudes et ta fenêtre d'éveil. »
  + ligne discrète « Fenêtre détectée ~7h–22h ».
- `plus` + cold-start : « On apprend tes habitudes… (rappels classiques en attendant). »
- `free` : le toggle continue de donner les rappels fixes ; ligne teaser **« Rappels adaptatifs »**
  avec `.premiumLocked(.adaptiveReminders)` → paywall, bénéfice surligné.

**Notifications adaptatives :** titre « Hydratation », corps type
« Tu n'as pas bu depuis un moment — un verre d'eau 💧 ? ». Actions **« Logger 250 ml »** +
**« Plus tard (1h) »** conservées.

**Post-séance + snooze :** inchangés, disponibles aux deux paliers (contextuels, non premium).

## Garde-fous & vie privée

- Espacement ≥ 90 min, plafond 6/jour, **jamais hors fenêtre d'éveil** (pas de rappel nocturne),
  **suppression dès objectif atteint**.
- Recalcul à chaque log/refresh (purge `wello.adaptif.*` puis repose).
- **Sommeil best-effort** : refus/vide géré par les replis ; **aucune donnée ne quitte
  l'appareil**. Conforme à « tout refus de permission géré, app pleinement utilisable ».

## Stratégie de test

- **Logique pure (`WelloKit`, `swift test`)** :
  - Détection des trous habituels sur historiques synthétiques (créneau récurrent détecté ;
    créneau sous le seuil ignoré).
  - Espacement ≥ 90 min et plafond 6/jour respectés.
  - Suppression de tous les rappels si objectif atteint.
  - Seuil cold-start : < 7 jours → signal d'insuffisance.
  - Dérivation de fenêtre : sommeil → historique → défaut ; bornes/percentiles.
  - Filtrage aux heures futures uniquement ; aucun rappel hors fenêtre.
- **Type-check iOS hors Xcode** : nouveaux fichiers couverts par les globs existants
  (`Services/*.swift`, `Views/*.swift`, `WelloKit/Sources/**`) → **pas de modif de la commande
  du `CLAUDE.md`**.
- **Previews** : `MockSleepWindow` + `MockStore` en `free` / `plus` / cold-start → états du profil.
- **Flux notifications réel (Xcode, manuel)** : sandbox de ton côté.

## Étapes Xcode manuelles

**Aucune nouvelle.** HealthKit déjà lié au target, `NSHealthShareUsageDescription` déjà présent.
La lecture sandbox du flux de notifications reste manuelle (non automatisable ici).

## Hors périmètre

- Réglages manuels (fenêtre, fréquence, sensibilité) — explicitement écartés (« tout auto »).
- Lecture des alarmes de l'app Horloge — impossible (pas d'API publique).
- `BGTaskScheduler` / recalcul nocturne en background — YAGNI (le recalcul à chaque refresh/log
  suffit).
- Apprentissage des heures habituelles de boire / courbe de rythme perso — autres modèles
  écartés au profit des trous récurrents.
- Autres features premium (export, thèmes, réglage avancé, widget) — specs ultérieurs.
