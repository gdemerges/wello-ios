# Base d'hydratation EFSA (par sexe) — Design

**Statut :** validé (brainstorming), prêt pour plan d'implémentation.
**Date :** 2026-06-04.

## Problème

La base actuelle `poids × 35 ml/kg` (ex. 2450 ml à 70 kg, avant tout bonus) **surestime** la cible
de boisson. Le coefficient 30–35 ml/kg est une règle clinique pour le besoin en eau **totale**
(boissons + aliments + eau métabolique) ; or l'alimentation fournit ~20–30 % de l'eau ingérée.
L'utiliser comme cible **de boisson** sur-compte donc d'environ 20–30 %. De plus, le besoin suit
surtout la masse maigre et la dépense énergétique, pas le poids total → le per-kg dérape aux
extrêmes.

## Décision

Adopter une base **fondée sur les apports de référence EFSA**, par sexe, exprimée en eau **à boire**.

- **Source :** EFSA (2010), *Scientific Opinion on Dietary Reference Values for water*,
  EFSA Journal 8(3):1459. Apport adéquat en eau **totale** : **2,5 L/j** (homme), **2,0 L/j**
  (femme), climat tempéré / activité modérée ; les boissons doivent fournir ~**80 %**.
- **Cible de boisson retenue :** homme **2000 ml**, femme **1600 ml** (80 % de 2,5 / 2,0 L).
- Le poids **ne pilote plus le calcul** et est **retiré** de l'app.

Les bonus activité (kcal HealthKit), météo (température ressentie), le plancher médical et le
plafond de sécurité 4000 ml sont **inchangés**. La personnalisation se fait désormais par
sexe + activité + météo + plancher, pas par poids.

## Périmètre

### Inclus
1. Base EFSA par sexe dans `HydrationCalculator` (constantes 2000/1600).
2. Nouvel enum pur `BiologicalSex` (WelloKit) ; `CalculatorInputs.weightKg` → `sex`.
3. Suppression complète du poids : `WeightResolver`, `UserProfile.weightKg`, lecture HealthKit
   `bodyMass`/`dernierPoids`, diagnostic `poidsDepuisSanté`, UI poids.
4. `sexe` ajouté au profil (optionnel ; nil = non renseigné) ; **choix forcé** à l'onboarding et
   re-demandé pour un profil migré sans sexe.
5. Mise à jour UI (Profil, BreakdownCard, Onboarding), previews, tests et docs.

### Exclu (YAGNI)
- Valeurs EFSA grossesse/allaitement (apports majorés) — hors périmètre d'une app perso.
- Ajustement par âge (35/30/25 ml/kg) — non pertinent puisqu'on quitte le per-kg.
- Recalcul rétroactif de l'historique (voir « Historique » ci-dessous).

## Architecture

### 1. WelloKit (logique pure, testable CLI)

**Nouveau** `WelloKit/Sources/WelloKit/Models/BiologicalSex.swift` :
```swift
/// Sexe biologique, base physiologique du besoin en eau (apports de référence EFSA).
public enum BiologicalSex: String, Sendable, CaseIterable {
    case homme
    case femme
    /// Libellé court français pour l'affichage.
    public var label: String { self == .homme ? "Homme" : "Femme" }
}
```

`HydrationCalculator.Constantes` : retirer `mlParKg` ; ajouter
```swift
/// Cible de boisson EFSA 2010 (eau totale 2,5 L/2,0 L, ~80 % via boissons).
public static let baseHommeML = 2000
public static let baseFemmeML = 1600
```

`CalculatorInputs` : remplacer `public let weightKg: Double` par `public let sex: BiologicalSex`
(init mis à jour en conséquence).

`HydrationCalculator.calculate` : `let base = inputs.sex == .homme ? Constantes.baseHommeML : Constantes.baseFemmeML`
(plus de multiplication ni d'arrondi). Le reste de la fonction est inchangé.

**Supprimer** `WeightResolver.swift`.

### 2. Modèle (app) & migration

`UserProfile` : retirer `weightKg`. Ajouter, sur le modèle des champs `quickAdd` (défaut inline pour
migration légère) :
```swift
/// Sexe biologique pour la base EFSA. Optionnel : nil = pas encore renseigné (force l'onboarding).
var sexeRaw: String? = nil
var sexe: BiologicalSex? {
    get { sexeRaw.flatMap(BiologicalSex.init(rawValue:)) }
    set { sexeRaw = newValue?.rawValue }
}
```
Migration : suppression d'une propriété + ajout d'un optionnel → **migration légère SwiftData**,
aucun plan custom. Le profil existant repart avec `sexe == nil`.

### 3. Choix forcé du sexe

- `RootView` présente le cover d'onboarding tant que `!hasOnboarded` **ou** `profil.sexe == nil`
  (RootView lit le profil via `store.profilCourant()`).
- `OnboardingView` : ajouter une étape interactive de sélection (Homme/Femme), avec un `@State`
  local `sexeChoisi: BiologicalSex?`. Le bouton final « Commencer » reste **désactivé tant que
  `sexeChoisi == nil`**. La closure de complétion devient `onTerminé(BiologicalSex)` (au lieu de
  `() -> Void`). C'est `RootView` qui reçoit le sexe, l'écrit dans `store.profilCourant().sexe`,
  pose `hasOnboarded = true`, puis appelle `store.refreshToday(force: true)`.
- `HydrationStore.refreshToday` : si `profil.sexe == nil`, poser `breakdown = nil` et sortir (aucun
  objectif tant que le sexe n'est pas renseigné — cohérent avec le gating ci-dessus).

### 4. HealthKit allégé

- `HealthKitServicing` : retirer `dernierPoids()`.
- `HealthKitService` : retirer `dernierPoids()`, `bodyMassType`, et **retirer `bodyMass` du set de
  lecture** (`read`).
- `Mocks.MockHealthKitService` : retirer `poids` et `dernierPoids()`.
- `HydrationStore.refreshToday` : retirer `dernierPoids()` + `résoudrePoids(...)` ; construire
  `CalculatorInputs(sex:activeEnergyKcal:weather:medicalFloorML:)`.
- `ÉtatServices` : retirer `poidsDepuisSanté` ; `tousOK` devient
  `météoDisponible && notificationsAutorisées`.

### 5. UI

- `ProfileView` : remplacer le `Stepper` poids par un `Picker` Homme/Femme lié à `profil.sexe`
  (mise à jour `updatedAt`). Retirer la ligne diagnostic « Santé (poids) ». Ajuster le commentaire
  d'en-tête.
- `BreakdownCard` : « Base (poids) » → « Base (EFSA) », icône `scalemass.fill` → `person.fill`.
- `PreviewSupport.container()` : `UserProfile(...)` avec `sexe` renseigné (`.homme`).
- `OnboardingView` : étape de choix (cf. §3) ; le texte de la page « objectif qui s'adapte » qui
  mentionne le poids est reformulé (sexe + activité + météo + plancher).

### 6. Tests (WelloKit, CLI)

- `HydrationCalculatorTests` : remplacer tous les `weightKg:` par `sex:`. Recalculer les attentes :
  base homme = 2000, femme = 1600. Renommer/adapter le « cas de base » ; **ajouter** un test
  « femme → base 1600 ». Les tests activité/météo/plancher/plafond conservent leur logique (seules
  les valeurs de base changent).
- **Supprimer** `WeightResolverTests.swift`.

### 7. Docs

- `README` : réécrire le bloc « Logique de calcul » (base EFSA par sexe, suppression du per-kg),
  mettre à jour la section permissions (plus de lecture du poids).
- `CLAUDE.md` : la carte du projet cite `WeightResolver` en exemple → remplacer par un exemple
  encore valide (ex. `HydrationCalculator`/`BiologicalSex`).

## Historique (décision explicite)

Les `DailyGoal` déjà enregistrés sont des **instantanés** de l'objectif visé ce jour-là : ils
**ne sont pas recalculés**. Seul le `DailyGoal` du jour courant est ré-upserté par `refreshToday`
avec la nouvelle base. L'historique mélange donc transitoirement anciennes et nouvelles bases —
acceptable et fidèle (un objectif passé reste ce qu'il était).

## Cas limites

- `sexe == nil` (profil migré, ou nouveau avant choix) → onboarding forcé, pas de calcul.
- Refus HealthKit/localisation/notifications → inchangé (l'app reste utilisable ; bonus à 0).
- Plancher médical ≥ base → l'objectif est piloté par le plancher (cas attendu pour l'utilisateur
  à plancher 2500), `plancherContraignant` déjà géré.

## Vérification

1. `cd WelloKit && swift test` → vert (calculateur réécrit, WeightResolver supprimé).
2. Type-check iOS hors Xcode (commande du `CLAUDE.md`) → 0 erreur.
3. Previews Xcode (manuel) : onboarding force le choix du sexe ; Profil montre le Picker ;
   BreakdownCard affiche « Base (EFSA) » à 2000/1600 ; un profil migré sans sexe re-déclenche
   l'onboarding.
