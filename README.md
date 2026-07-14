# Wello — Suivi d'hydratation (iOS)

App iOS personnelle, mono-utilisateur, 100 % locale. Calcule un objectif d'hydratation
quotidien personnalisé (sexe, activité HealthKit, météo Open-Meteo, contexte médical) et
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

1. Ouvrir `Wello/Wello.xcodeproj` dans Xcode 26+ (cible iOS 18+).
2. **Lier le package local** : File ▸ Add Package Dependencies ▸ Add Local ▸ choisir le dossier
   `WelloKit`, puis ajouter la bibliothèque `WelloKit` au target `Wello`.
3. Vérifier que les fichiers de `Wello/Wello/` (App, Models, Services, Views) appartiennent au
   target `Wello` (avec les groupes synchronisés Xcode 16+, ils sont pris en compte
   automatiquement ; sinon, *Add Files to "Wello"*).
4. Configurer les capabilities & l'Info.plist (voir ci-dessous).
5. Cmd+R sur un simulateur ou un device iOS 18+.

## Tests de la logique métier

La logique critique (`HydrationCalculator`, `BiologicalSex`) vit dans le package `WelloKit`
et se teste sans Xcode :

```bash
cd WelloKit && swift test
```

## Permissions

Activer la capability **HealthKit** sur le target (Signing & Capabilities ▸ + Capability ▸
HealthKit), y cocher **Background Delivery**, et renseigner dans l'Info.plist du target :

- `NSHealthShareUsageDescription` — lecture des séances et de l'énergie active.
- `NSHealthUpdateUsageDescription` — écriture des prises d'eau dans Santé.app.
- `NSLocationWhenInUseUsageDescription` — localisation pour la météo locale.

Les notifications sont demandées à l'usage. **Tous les refus sont gérés** : l'app reste
pleinement utilisable en saisie manuelle (activité = 0, météo = bonus 0, pas de rappels).

**Arrière-plan** : Wello observe les séances et les prises d'eau externes via `HKObserverQuery` +
background delivery. Une séance terminée relève l'objectif, replanifie les rappels et rafraîchit
widget et Live Activity sans que l'app soit ouverte. Le réveil n'interroge pas le GPS (météo lue
en cache) : hors premier plan, un fix est lent et le réveil doit être acquitté rapidement.

## Effacer ses données

Profil ▸ **Confidentialité**, deux gestes distincts :

- **Effacer mon historique** — prises, objectifs et caches locaux. Le profil survit, l'objectif du
  jour est recalculé aussitôt : pas d'onboarding à refaire.
- **Tout effacer et repartir de zéro** — le profil en plus : l'app revient à son premier lancement.

Les deux proposent de supprimer aussi les prises d'eau écrites par Wello dans Santé.app (jamais
celles des autres apps : HealthKit l'interdit — elles sont simplement marquées pour ne pas être
réimportées). Les achats Wello+ sont conservés dans les deux cas.

## Logique de calcul

```
base          = 2000 ml (homme) | 1600 ml (femme)        // apport de boisson EFSA
activité      = min(énergie active kcal × 1, 1000)       // 1 ml/kcal (HealthKit), plafonné
météo         = min(max(0, ressentie°C − 27) × 50, 600)  // ressentie = apparent temp, 0 si indispo
altitude      = min(max(0, alt − 2000)/1000 × 150, 500)  // Open-Meteo, 0 en plaine/indispo
corpulence    = clamp(base × 0,5 × (poids−réf)/réf, ±400) // Wello+, réf 70/60 kg ; 0 si non activé
physiologique = max(0, base + activité + météo + altitude + physioÉtat + rénal + corpulence + ajust. manuel)
total         = min(4000, physiologique)                 // unique garde-fou : le plafond global
```

La base provient des **apports de référence EFSA (2010)** : eau totale 2,5 L/j (homme), 2,0 L/j
(femme), dont ~80 % via les boissons → cible de boisson **2000 ml / 1600 ml**. On ne part pas du
poids (× 35 ml/kg) : ce coefficient estime l'eau *totale* (boissons + aliments + eau métabolique)
et surestime la cible de boisson de ~20-30 %. La personnalisation se fait par sexe + activité
(kcal) + météo. Il n'y a **pas de plancher** : la base EFSA en tient lieu — seuls des réglages
explicitement choisis par l'utilisateur (corpulence, ajustement manuel, tous deux Wello+ et
bornés) peuvent la faire descendre. L'unique garde-fou est le **plafond global de 4000 ml**, qui
borne le total quel que soit le cumul des bonus.

Le bonus d'activité dérive de l'**énergie active brûlée** (kcal, HealthKit) plutôt que de la
seule durée : la perte sudorale à l'effort est proportionnelle à la chaleur métabolique
produite. Évaporer 1 mL de sueur dissipe ~0,58 kcal et l'essentiel de l'énergie d'exercice
devient chaleur → **~1 mL d'eau par kcal** (coefficient conservateur, plafonné à 1000 ml).

Le bonus météo s'appuie sur la **température ressentie** (apparent temperature d'Open-Meteo),
qui combine déjà chaleur, humidité, vent et rayonnement — un seul indicateur cohérent du stress
thermique. Montée linéaire de **50 mL par °C ressenti au-dessus de 27 °C** (zone de confort),
plafonnée à 600 mL. Un 30 °C sec (sueur qui s'évapore) et un 30 °C humide (qui ne s'évapore plus)
donnent ainsi des ressentis — et des besoins — très différents.

Le bonus **altitude** (élévation Open-Meteo) ajoute **+150 mL par 1000 m au-dessus de 2000 m**
(plafond 500 mL) : en altitude, l'air sec et l'hyperventilation majorent les pertes hydriques.

L'ajustement de **corpulence** (Wello+, opt-in) module la base EFSA selon le poids : une fraction
**bornée à ±400 mL** de l'écart relatif à un poids de référence (70 kg homme / 60 kg femme). On
n'adopte **pas** le « 35 mL/kg » (qui estime l'eau *totale* et surestime la cible de boisson) — la
corpulence ne fait qu'*affiner* le socle EFSA. Le calcul complet et ses sources sont exposés dans
l'app via l'écran **« Méthode »** (chaque ligne du détail de l'objectif est tappable).

## Où ajuster l'objectif

Onglet **Profil** : le sexe fixe la base EFSA ; l'état physiologique (grossesse/allaitement) et le
besoin rénal (lithiase, 500–1500 ml) ajoutent leurs termes. En **Wello+**, la section « Réglage
avancé » ouvre les sensibilités effort/chaleur (×0,5–1,5), l'ajustement manuel et la corpulence.
Le plafond de 4000 ml s'applique toujours.

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
lancement). L'ajout rapide écrit une prise sans ouvrir l'app (App Intents).

## App Apple Watch (Phase 2 — livrée)

App Watch autonome : jauge de progression + ajout rapide d'eau au poignet, utilisable hors-ligne.
Synchronisation **sans CloudKit** entre deux appareils via **WatchConnectivity** : l'iPhone pousse
l'objectif/consommé du jour (mirroir coalescé, `updateApplicationContext`) ; la Watch met ses prises
en file (`transferUserInfo`, livraison garantie) et les envoie à l'iPhone, **unique écrivain
HealthKit** (déduplication par `watchUUID`, pas de double compte). La Watch lit l'énergie active
(HealthKit) pour faire monter la part « activité » de l'objectif en séance, même iPhone absent. La
réconciliation du consommé (`consommé = total iPhone + prises locales non acquittées`) est une
logique pure testée dans WelloKit (`ÉtatHydratationWatch`).

**Complication de cadran (livrée)** : extension WidgetKit watchOS (`WelloWatchWidget`) exposant les
familles `.accessoryCircular` / `.accessoryCorner` / `.accessoryInline` / `.accessoryRectangular`.
Elle tourne dans un process séparé : l'app Watch publie son dernier `WidgetProgress` dans un
conteneur App Group **local à la montre** (`group.Life.Wello`, `WelloWatchShared`) et déclenche
`WidgetCenter.reloadAllTimelines()` à chaque prise/synchronisation.
