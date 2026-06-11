# Wello — Suivi d'hydratation (iOS)

App iOS personnelle, mono-utilisateur, 100 % locale. Calcule un objectif d'hydratation
quotidien personnalisé (sexe, activité HealthKit, météo Open-Meteo, plancher médical) et
aide à le suivre.

## Arborescence

```
Wello/                          ← racine
├─ WelloKit/                    ← Swift Package : logique métier pure (testable en CLI)
├─ Wello/                       ← projet Xcode
│  ├─ Wello.xcodeproj
│  └─ Wello/                    ← sources de l'app (App, Models, Services, Views)
├─ docs/                        ← spec et plan d'implémentation
└─ README.md
```

## Lancement

1. Ouvrir `Wello/Wello.xcodeproj` dans Xcode 26+ (cible iOS 17+).
2. **Lier le package local** : File ▸ Add Package Dependencies ▸ Add Local ▸ choisir le dossier
   `WelloKit`, puis ajouter la bibliothèque `WelloKit` au target `Wello`.
3. Vérifier que les fichiers de `Wello/Wello/` (App, Models, Services, Views) appartiennent au
   target `Wello` (avec les groupes synchronisés Xcode 16+, ils sont pris en compte
   automatiquement ; sinon, *Add Files to "Wello"*).
4. Configurer les capabilities & l'Info.plist (voir ci-dessous).
5. Cmd+R sur un simulateur ou un device iOS 17+.

## Tests de la logique métier

La logique critique (`HydrationCalculator`, `BiologicalSex`) vit dans le package `WelloKit`
et se teste sans Xcode :

```bash
cd WelloKit && swift test
```

## Permissions

Activer la capability **HealthKit** sur le target (Signing & Capabilities ▸ + Capability ▸
HealthKit), et renseigner dans l'Info.plist du target :

- `NSHealthShareUsageDescription` — lecture des séances et de l'énergie active.
- `NSHealthUpdateUsageDescription` — écriture des prises d'eau dans Santé.app.
- `NSLocationWhenInUseUsageDescription` — localisation pour la météo locale.

Les notifications sont demandées à l'usage. **Tous les refus sont gérés** : l'app reste
pleinement utilisable en saisie manuelle (activité = 0, météo = bonus 0, pas de rappels).

## Logique de calcul

```
base          = 2000 ml (homme) | 1600 ml (femme)        // apport de boisson EFSA
activité      = min(énergie active kcal × 1, 1000)       // 1 ml/kcal (HealthKit), plafonné
météo         = min(max(0, ressentie°C − 27) × 50, 600)  // ressentie = apparent temp, 0 si indispo
physiologique = base + activité + météo
total         = min(4000, max(plancher médical, physiologique))
```

La base provient des **apports de référence EFSA (2010)** : eau totale 2,5 L/j (homme), 2,0 L/j
(femme), dont ~80 % via les boissons → cible de boisson **2000 ml / 1600 ml**. On ne part pas du
poids (× 35 ml/kg) : ce coefficient estime l'eau *totale* (boissons + aliments + eau métabolique)
et surestime la cible de boisson de ~20-30 %. La personnalisation se fait par sexe + activité
(kcal) + météo, et le **plancher médical** reste prioritaire.

Le bonus d'activité dérive de l'**énergie active brûlée** (kcal, HealthKit) plutôt que de la
seule durée : la perte sudorale à l'effort est proportionnelle à la chaleur métabolique
produite. Évaporer 1 mL de sueur dissipe ~0,58 kcal et l'essentiel de l'énergie d'exercice
devient chaleur → **~1 mL d'eau par kcal** (coefficient conservateur, plafonné à 1000 ml).

Le bonus météo s'appuie sur la **température ressentie** (apparent temperature d'Open-Meteo),
qui combine déjà chaleur, humidité, vent et rayonnement — un seul indicateur cohérent du stress
thermique. Montée linéaire de **50 mL par °C ressenti au-dessus de 27 °C** (zone de confort),
plafonnée à 600 mL. Un 30 °C sec (sueur qui s'évapore) et un 30 °C humide (qui ne s'évapore plus)
donnent ainsi des ressentis — et des besoins — très différents.

## Où ajuster le plancher médical

Onglet **Profil** ▸ section « Plancher médical » (1000–4000 ml). Valeur par défaut : 2500 ml.

## Architecture

- `WelloKit/` — logique pure testable (calcul d'objectif, base EFSA par sexe).
- `Wello/Wello/Models` — modèles SwiftData (`UserProfile`, `DailyGoal`, `HydrationLog`).
- `Wello/Wello/Services` — HealthKit, météo, localisation, notifications, `HydrationStore`.
- `Wello/Wello/Views` — écrans SwiftUI (Principal, Historique, Profil) + composants.

Pattern « MV » : pas de ViewModels ; les vues utilisent `@Query` SwiftData et un
`HydrationStore` `@Observable` injecté via l'environnement. Services derrière des protocoles
(mocks fournis pour les previews).

## Accessibilité

- **VoiceOver** : la jauge expose une valeur lisible (« X ml sur Y, Z % ») ; les boutons d'eau
  annoncent « Ajouter N millilitres » ; chaque barre du graphe d'historique porte sa date et son
  taux d'atteinte ; les icônes décoratives sont masquées au lecteur d'écran.
- **Annonces** : l'atteinte de l'objectif déclenche une annonce VoiceOver, en plus de la bannière
  visuelle et du retour haptique.
- **Dynamic Type** : l'app utilise des styles typographiques qui s'adaptent ; les quelques tailles
  d'affichage fixes (compteur de la jauge, wordmark, illustrations d'onboarding) suivent les
  réglages via `@ScaledMetric`, avec repli `minimumScaleFactor` pour éviter la troncature.
- **Reduce Motion** : si l'option iOS est activée, la vague de la jauge reste dessinée mais cesse
  d'onduler, les montées de niveau deviennent instantanées et les animations « ressort »
  (célébration, pulsation des boutons) sont neutralisées — sans rien retirer aux autres
  utilisateurs.
- **Contraste & couleur** : retour haptique et libellés texte doublent l'information portée par la
  couleur (objectif atteint, états du diagnostic) ; ombre de lisibilité sur le texte des boutons
  d'eau en clair comme en sombre. Zones tactiles ≥ 44 pt.

## Hors périmètre (Phase 1)

watchOS, complication Watch — prévus en Phase 2. Le découpage services/calculateur
est conçu pour les accueillir sans refonte. Le partage de données app ↔ widget se fera via un
App Group (pas de CloudKit : l'app est volontairement locale et mono-appareil).

## Widget iOS (Phase 2 — livré)

Widgets d'écran d'accueil (petit : anneau d'objectif ; moyen : barre + boutons d'ajout rapide
+150/+250/+500) et accessoire d'écran verrouillé (anneau). Partage de données app↔widget via
l'App Group `group.Life.Wello` (store SwiftData unique, migré depuis le store local au premier
lancement). L'ajout rapide écrit une prise sans ouvrir l'app (App Intents, iOS 17).
watchOS / complication Watch restent prévus en Phase 2.
