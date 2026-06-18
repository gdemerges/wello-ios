# Réglage avancé du calcul (Wello+) — Design

**Statut :** livré.
**Date :** 2026-06-18.

## Problème

`PremiumFeature.advancedTuning` existe dans l'enum sans implémentation ni sens défini. Le calcul
d'objectif repose sur des constantes fixes ; aucun moyen pour l'utilisateur averti de l'ajuster.

## Décision

Livrer un **réglage avancé** (Wello+) à trois paramètres, tous **neutres par défaut** (objectif
standard inchangé). Les **plafonds de sécurité restent intouchables** (activité 1000, météo 600,
plafond global 4000 ml ; total borné ≥ 0).

1. **Sensibilité à l'effort** : multiplie le bonus d'activité avant son plafond. ×0,5–1,5.
2. **Sensibilité à la chaleur** : multiplie le bonus météo avant son plafond. ×0,5–1,5.
3. **Ajustement manuel** : terme additif fixe (peut être négatif). −500…+500 ml, pas de 50.

## Architecture

### WelloKit (pur, testé)
- `CalculatorTuning` (`activityMultiplier`, `weatherMultiplier`, `manualAdjustmentML`) ; `.neutre` ;
  **init bornant** chaque valeur (saisie aberrante neutralisée) ; `multiplierRange`/`adjustmentLimit`.
- `CalculatorInputs.tuning: CalculatorTuning = .neutre` (rétro-compatible).
- `HydrationCalculator.calculate` : multiplicateurs **avant** plafonds ; ajustement manuel dans la
  somme ; total `min(4000, max(0, …))`.
- `GoalBreakdown.manualAdjustmentML` (nouveau terme additif, défaut 0) ; `physiologicalML` borné ≥ 0.

### App
- `UserProfile` : `activitySensitivity` / `weatherSensitivity` / `manualAdjustmentML` (défauts inline
  neutres → migration légère) ; `tuning` (assemblé, borné) ; `réglageAvancéModifié`.
- `DailyGoal.manualAdjustmentML` (défaut inline) — terme persisté comme les autres ; upsert mis à jour.
- `HydrationStore.refreshToday` : passe `profil.tuning` au calcul.
- `ProfileView` : section « Réglage avancé » gatée `.advancedTuning` (sinon teasing → paywall) :
  2 steppers de sensibilité + stepper d'ajustement + « Réinitialiser » si non neutre. Chaque
  changement → `updatedAt` + `refreshToday(force:)`.
- `BreakdownCard` : ligne « Réglage avancé » signée quand l'ajustement ≠ 0.

## Cas limites
- Réglage neutre → objectif identique au standard (test de non-régression).
- Multiplicateurs amplifiés → bonus toujours plafonnés (activité 1000, météo 600).
- Ajustement très négatif → total borné ≥ 0 ; très positif → plafond global 4000 appliqué.
- Valeurs hors plage (corruption) → bornées à l'init de `CalculatorTuning`.
- Historique : les `DailyGoal` passés ne sont pas recalculés (instantanés), comme pour la base EFSA.

## Vérification
1. `cd WelloKit && swift test` → vert (suite `CalculatorTuning`, +8 tests ; 86 au total).
2. Type-check iOS app + widget → 0 erreur.
3. Manuel : en Wello+, modifier les curseurs recalcule l'objectif et la BreakdownCard ; en gratuit,
   la section renvoie au paywall.
