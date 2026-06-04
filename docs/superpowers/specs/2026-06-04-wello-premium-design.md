# Wello — Mode premium (« Wello+ ») — Design

**Date :** 2026-06-04
**Statut :** Validé pour implémentation
**Pré-requis :** Phase 1 (cœur iOS) livré — voir `2026-06-03-wello-hydratation-design.md`

## Contexte & objectif

Wello vise à terme une publication sur l'App Store en **freemium**. Ce spec définit le
**mode premium « Wello+ »** : l'infrastructure de monétisation (StoreKit, statut
d'entitlement, gating, paywall) et la première feature payante livrée au lancement.

**Posture produit (décisions validées en brainstorming) :**

- **Local-first par défaut, cloud ouvert si la valeur le justifie.** Le premium de lancement
  reste 100 % local — aucun backend, aucun compte.
- **Modèle hybride :** achat unique « lifetime » pour les features locales ; un éventuel
  abonnement serait réservé à de futures fonctions cloud (synchro/sauvegarde) — **hors
  périmètre de ce spec**.
- **Le cœur gratuit doit rester excellent** : le calcul d'objectif intelligent
  (poids/activité/météo), la saisie et la jauge restent gratuits. C'est le hook.

## Périmètre de ce spec

« Mode premium » recouvre deux choses ; ce spec les sépare nettement :

- **(a) La plomberie** — achat StoreKit 2, statut d'entitlement, gating réutilisable,
  paywall. **C'est le cœur de ce spec.**
- **(b) Les features premium** — la plupart n'existent pas encore. Ce spec en livre **une
  seule** (la feature phare). Les autres (analyses avancées, export, thèmes, types de
  boissons, rappels adaptatifs, réglage avancé, Widget/Watch) feront chacune l'objet d'un
  spec/plan de suivi.

**Feature phare au lancement = « Historique illimité ».** SwiftData conserve déjà toutes les
prises ; le gating (gratuit = 7 derniers jours, premium = tout) se pose donc sur des données
qui existent déjà, sans dépendre d'une feature à finir.

## Carte des paliers

| Capacité | Gratuit | Wello+ (lifetime) |
|---|---|---|
| Calcul d'objectif intelligent (poids/activité/météo) | ✅ *(le hook)* | ✅ |
| Saisie manuelle + sync HealthKit | ✅ | ✅ |
| Jauge du jour | ✅ | ✅ |
| **Historique** | **7 derniers jours** | **illimité** *(feature phare de ce spec)* |
| Analyses (tendances, séries, moyennes) | — | ✅ *(spec ultérieur)* |
| Rappels | fixes (existants) | adaptatifs *(spec ultérieur)* |
| Types de boissons + coefficients (café/thé/alcool) | — | ✅ *(spec ultérieur)* |
| Réglage avancé du calcul | — | ✅ *(spec ultérieur)* |
| Export CSV/PDF | — | ✅ *(spec ultérieur)* |
| Thèmes + icônes alternatives | — | ✅ *(spec ultérieur)* |
| Widget / Watch *(Phase 2)* | — | ✅ *(spec ultérieur)* |

Les `enum` couvrent dès maintenant toutes les features prévues, pour que chaque spec de
suivi n'ait qu'à brancher son gating sans toucher l'infrastructure.

## Stack

- StoreKit 2 (`Product`, `Transaction.currentEntitlements`, `Transaction.updates`, `purchase()`)
- SwiftUI / SwiftData / Swift 6 strict concurrency (cohérent avec l'existant)
- Logique de gating pure dans `WelloKit` (testable en CLI)
- Commentaires en français, idiomatique SwiftUI

## Décisions d'architecture validées

Tout se coule dans les patterns existants : **logique pure dans `WelloKit`**, **service
derrière protocole + mock**, **store `@Observable` injecté via `.environment`**.

### Logique pure — `WelloKit/Sources/WelloKit/`

- `enum PremiumFeature` : `unlimitedHistory`, `analytics`, `customDrinks`, `advancedTuning`,
  `export`, `themes`, `adaptiveReminders`, `widget`.
- `enum EntitlementStatus { case free, plus }`.
- `struct Entitlements { let status; func isUnlocked(_ f: PremiumFeature) -> Bool }` — la
  table palier → features, en un **seul endroit testable**. `free` ne déverrouille rien ;
  `plus` déverrouille tout.
- `func historyVisibleSince(status:now:) -> Date?` — `nil` = illimité ; `free` →
  `now − 7 jours`. La feature phare se teste ainsi sans Xcode.

### Couche app — `Wello/Wello/Services/`

- `protocol StoreServicing: Sendable` :
  - `func currentStatus() async -> EntitlementStatus`
  - `func produitPlus() async -> StoreProduct?` *(prix localisé, jamais codé en dur)*
  - `func acheter() async throws -> PurchaseOutcome` *(`success` / `userCancelled` / `pending`)*
  - `func restaurer() async -> EntitlementStatus`
  - `func observerTransactions() -> AsyncStream<EntitlementStatus>`
- `StoreKitService` : implémentation réelle StoreKit 2 (listener `Transaction.updates` pour
  capter achats/remboursements hors app).
- `MockStoreService` (dans `Mocks.swift`) : configurable `free` / `plus`, pour previews.
- `EntitlementStore` `@MainActor @Observable` : détient `status`, expose `isUnlocked(_:)`,
  méthodes `acheterPlus()` / `restaurer()`, écoute `Transaction.updates`. Injecté dans
  `WelloApp` et lu via `@Environment(EntitlementStore.self)` — comme `HydrationStore`.

### Produit & configuration StoreKit

- 1 produit **non-consommable** : `com.wello.plus.lifetime`.
- Fichier `Wello.storekit` (créé dans Xcode — **étape manuelle**) pour tester l'achat en local.

### Gating dans les vues — `Wello/Wello/Views/`

- Modifier réutilisable `.premiumLocked(_ feature:)` : floute/teasing + ouvre le paywall au
  tap, avec le bénéfice concerné mis en avant.
- `HistoryView` : affiche 7 jours en gratuit, puis une section « verrouillée » au-delà ;
  borne la requête via `historyVisibleSince(...)`.

## UX du paywall & points d'entrée

**Points d'entrée :**
1. **Profil** — ligne « Wello+ » en haut (« Débloquer tout », ou badge « Actif » si acheté).
2. **Gating contextuel** — tap sur une zone verrouillée → paywall avec le bénéfice déclencheur
   surligné (meilleure conversion qu'un mur générique).

**Pas de paywall à l'onboarding** : l'utilisateur découvre d'abord la valeur du cœur gratuit.

**`PaywallView` (présenté en `.sheet`) :**
- En-tête : « Wello+ » + tagline.
- Liste des bénéfices (SF Symbols + libellés), bénéfice déclencheur surligné.
- **Prix localisé** lu depuis StoreKit.
- Bouton principal : « Débloquer — {prix} » (achat unique).
- **« Restaurer mes achats »** *(obligatoire App Store)*.
- **Liens Conditions d'utilisation + Confidentialité** *(obligatoires App Store)*.
- États : en cours (spinner) / succès (confirmation + dismiss) / annulé (retour silencieux) /
  échec (message).
- Accessibilité cohérente avec l'app : Dynamic Type, VoiceOver, Reduce Motion.

**Après achat** : `EntitlementStore.status` passe à `plus` → les zones verrouillées se
déverrouillent réactivement (`@Observable`) ; badge « Wello+ » dans le Profil.

## Gestion d'erreur & offline

- `Transaction.currentEntitlements` est local après la 1ʳᵉ synchro → lecture au lancement.
- **Cache du dernier statut connu** en `UserDefaults` (comme la météo) : si offline, on
  honore le dernier `plus` connu. Règle d'or : **jamais déverrouiller à tort, jamais
  verrouiller un client payant**.
- Achat annulé / en attente / échoué : remontés proprement dans le paywall, sans crash.

## Stratégie de test

- **Logique pure (`WelloKit`, `swift test`)** :
  - `Entitlements.isUnlocked(_:)` — `free` verrouille tout sauf le cœur ; `plus` déverrouille tout.
  - `historyVisibleSince(status:now:)` — `free` → `now − 7 j` exactement (bornes testées) ;
    `plus` → `nil`.
- **Type-check iOS hors Xcode** : les nouveaux fichiers (`StoreServicing`, `EntitlementStore`,
  `PaywallView`, modifier de gating) passent `swiftc -typecheck`.
  **À faire :** ajouter ces fichiers à la commande de vérification du `CLAUDE.md`.
- **Previews** : `MockStoreService` (`free` / `plus`) → paywall, `HistoryView` verrouillée vs
  déverrouillée, badge Profil — sans compte sandbox.
- **Flux d'achat réel (Xcode, manuel)** : `Wello.storekit` + scheme → achat, restauration,
  annulation, cas offline. **Non automatisable hors Xcode** (de ton côté).

## Étapes Xcode manuelles (non automatisables ici)

- Créer le produit non-consommable `com.wello.plus.lifetime` (App Store Connect) et le
  fichier `Wello.storekit` local + le lier au scheme.
- Capability **In-App Purchase** sur le target.
- Préparer les pages **Conditions d'utilisation** et **Confidentialité** (URLs liées au paywall).

## Hors périmètre

- Toute fonction **cloud** (synchro iCloud, sauvegarde, multi-appareils) et son **abonnement**.
- Les autres features premium (analyses, export, thèmes, types de boissons, rappels adaptatifs,
  réglage avancé, Widget/Watch) — chacune un spec/plan ultérieur.
- A/B-test du moment d'affichage du paywall.
