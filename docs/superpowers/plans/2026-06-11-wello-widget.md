# Widget iOS (Phase 2) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ajouter des widgets iOS (petit anneau + moyen interactif + accessoire écran verrouillé) qui lisent l'hydratation du jour depuis un store SwiftData partagé via App Group, et permettent un ajout rapide d'eau sans ouvrir l'app.

**Architecture:** Le `ModelContainer` migre vers un store dans l'App Group `group.Life.Wello` (fabrique partagée `WelloShared`, migration unique du store local). L'extension widget lit `DailyGoal` + somme des `HydrationLog.effectiveML` du jour ; un `AddWaterIntent` (App Intents, iOS 17) insère une prise dans le store partagé et recharge les timelines. Le calcul d'affichage est un type pur `WidgetProgress` dans WelloKit, testé en CLI.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, WidgetKit, AppIntents, Swift Testing (`swift test`). Patterns existants : logique pure WelloKit, pattern MV.

**Spec :** `docs/superpowers/specs/2026-06-11-wello-widget-design.md`.

> **Branche :** déjà sur `feat/widget` (le spec y est commité). Trailer de commit :
> `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.

**Note de vérification :** tâches WelloKit → `cd WelloKit && swift test`. Tâches app → type-check iOS hors Xcode (voir `CLAUDE.md`). Le code de l'**extension widget** (WidgetKit/AppIntents/SwiftData macros + cible Xcode) n'est pas pilotable en CLI : il est fourni complet et validé en **preview Xcode** par l'utilisateur (Task 4/5). Un type-check best-effort est proposé mais non bloquant.

---

## File Structure

**Créés :**
- `WelloKit/Sources/WelloKit/Models/WidgetProgress.swift` — calcul d'affichage pur (fraction, %, libellés).
- `WelloKit/Tests/WelloKitTests/WidgetProgressTests.swift` — tests du calcul.
- `Wello/Wello/App/WelloShared.swift` — App Group ID + fabrique `ModelContainer` partagée + migration (membership app **et** widget).
- `Wello/WelloWidget/WelloWidgetBundle.swift` — point d'entrée `@main` de l'extension.
- `Wello/WelloWidget/WelloWidget.swift` — `Widget`, `Provider`, `Entry`.
- `Wello/WelloWidget/WelloWidgetViews.swift` — vues des familles (petit/moyen/accessoryCircular).
- `Wello/WelloWidget/AddWaterIntent.swift` — App Intent d'ajout rapide.

**Modifiés :**
- `Wello/Wello/App/WelloApp.swift` — utilise `WelloShared.makeModelContainer()`.
- `Wello/Wello/Services/HydrationStore.swift` — recharge des widgets après mutation.
- `README.md`, `CLAUDE.md` — docs Phase 2 (widget, App Group).

---

## Task 1 : `WidgetProgress` (WelloKit, TDD)

**Files:**
- Create: `WelloKit/Sources/WelloKit/Models/WidgetProgress.swift`
- Test: `WelloKit/Tests/WelloKitTests/WidgetProgressTests.swift`

- [ ] **Step 1 : Écrire le fichier de tests (rouge)**

Create `WelloKit/Tests/WelloKitTests/WidgetProgressTests.swift` :

```swift
import Testing
@testable import WelloKit

@Suite("WidgetProgress")
struct WidgetProgressTests {

    @Test("Mi-parcours : fraction 0.5, 50 %")
    func miParcours() {
        let p = WidgetProgress(consomméML: 1150, objectifML: 2300)
        #expect(p.fraction == 0.5)
        #expect(p.pourcent == 50)
    }

    @Test("Objectif atteint : fraction bridée à 1.0, 100 %")
    func atteint() {
        let p = WidgetProgress(consomméML: 2300, objectifML: 2300)
        #expect(p.fraction == 1.0)
        #expect(p.pourcent == 100)
    }

    @Test("Dépassement : pourcent réel > 100, fraction bridée à 1.0")
    func dépassement() {
        let p = WidgetProgress(consomméML: 2500, objectifML: 2000)
        #expect(p.fraction == 1.0)
        #expect(p.pourcent == 125)
    }

    @Test("Consommé négatif (boisson diurétique) : clampé à 0 %")
    func négatif() {
        let p = WidgetProgress(consomméML: -50, objectifML: 2000)
        #expect(p.fraction == 0.0)
        #expect(p.pourcent == 0)
    }

    @Test("Objectif nul (non configuré) : 0 sans division par zéro")
    func objectifNul() {
        let p = WidgetProgress(consomméML: 500, objectifML: 0)
        #expect(p.fraction == 0.0)
        #expect(p.pourcent == 0)
    }

    @Test("Libellés en français : litres et pourcent")
    func libellés() {
        let p = WidgetProgress(consomméML: 1400, objectifML: 2300)
        #expect(p.consomméLitres == "1,4")
        #expect(p.objectifLitres == "2,3")
        #expect(p.libelléValeurs == "1,4 / 2,3 L")
        #expect(p.libelléPourcent == "61 %")
    }

    @Test("Formatage litres : un chiffre après la virgule, arrondi")
    func formatLitres() {
        #expect(WidgetProgress(consomméML: 500, objectifML: 2000).consomméLitres == "0,5")
        #expect(WidgetProgress(consomméML: 2000, objectifML: 2000).objectifLitres == "2,0")
        #expect(WidgetProgress(consomméML: 1950, objectifML: 2000).consomméLitres == "2,0")
    }
}
```

- [ ] **Step 2 : Lancer les tests pour vérifier l'échec**

Run: `cd WelloKit && swift test --filter WidgetProgress`
Expected: FAIL — `cannot find 'WidgetProgress' in scope`.

- [ ] **Step 3 : Créer `WidgetProgress.swift`**

Create `WelloKit/Sources/WelloKit/Models/WidgetProgress.swift` :

```swift
import Foundation

/// Calcul d'affichage pour les widgets : dérive d'un couple (consommé, objectif) en ml
/// la fraction de remplissage, le pourcentage et les libellés français formatés.
/// Pur et testable en CLI ; ne dépend ni de SwiftUI ni de SwiftData.
public struct WidgetProgress: Sendable, Equatable {
    /// Consommé brut du jour (peut être négatif si des boissons diurétiques sont saisies).
    public let consomméML: Int
    /// Objectif du jour (0 si non encore calculé / non configuré).
    public let objectifML: Int

    public init(consomméML: Int, objectifML: Int) {
        self.consomméML = consomméML
        self.objectifML = objectifML
    }

    /// Consommé borné à 0 (un total négatif n'a pas de sens pour l'affichage).
    private var consomméClampé: Int { max(0, consomméML) }

    /// Fraction de remplissage bornée 0…1 (pour l'anneau / la barre).
    public var fraction: Double {
        guard objectifML > 0 else { return 0 }
        return min(1, Double(consomméClampé) / Double(objectifML))
    }

    /// Pourcentage réel, arrondi (peut dépasser 100 ; 0 si objectif nul).
    public var pourcent: Int {
        guard objectifML > 0 else { return 0 }
        return Int((Double(consomméClampé) / Double(objectifML) * 100).rounded())
    }

    /// Litres consommés, un chiffre après la virgule décimale française. Ex. "1,4".
    public var consomméLitres: String { Self.litres(consomméClampé) }
    /// Litres de l'objectif, format français. Ex. "2,3".
    public var objectifLitres: String { Self.litres(objectifML) }

    /// "1,4 / 2,3 L"
    public var libelléValeurs: String { "\(consomméLitres) / \(objectifLitres) L" }
    /// "61 %"
    public var libelléPourcent: String { "\(pourcent) %" }

    /// Formate des ml en litres « x,y » indépendamment de la locale système (déterministe).
    private static func litres(_ ml: Int) -> String {
        let s = String(format: "%.1f", Double(ml) / 1000)
        return s.replacingOccurrences(of: ".", with: ",")
    }
}
```

- [ ] **Step 4 : Lancer les tests pour vérifier le succès**

Run: `cd WelloKit && swift test --filter WidgetProgress`
Expected: PASS (8 tests).

- [ ] **Step 5 : Lancer toute la suite (non-régression)**

Run: `cd WelloKit && swift test`
Expected: PASS (suite complète au vert).

- [ ] **Step 6 : Commit**

```bash
git add WelloKit/Sources/WelloKit/Models/WidgetProgress.swift \
  WelloKit/Tests/WelloKitTests/WidgetProgressTests.swift
git commit -m "feat(kit): WidgetProgress — calcul d'affichage des widgets (pur, testé)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2 : Store partagé App Group + migration (app)

**Files:**
- Create: `Wello/Wello/App/WelloShared.swift`
- Modify: `Wello/Wello/App/WelloApp.swift:16-18`

- [ ] **Step 1 : Créer `WelloShared.swift`**

Create `Wello/Wello/App/WelloShared.swift` :

```swift
import Foundation
import SwiftData

/// Configuration partagée entre l'app et l'extension widget : identifiant d'App Group et
/// fabrique du `ModelContainer` pointant vers un store unique dans le conteneur d'App Group.
/// Effectue une migration unique du store local historique vers l'App Group au premier accès.
enum WelloShared {
    /// Doit correspondre à la capability App Group activée sur l'app ET l'extension widget.
    static let appGroupID = "group.Life.Wello"

    /// Store partagé, dans le conteneur d'App Group (lisible/écrivable par les deux cibles).
    static var sharedStoreURL: URL {
        let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)!
        return dir.appendingPathComponent("Wello.store")
    }

    /// Store local historique (créé par les versions pré-widget, container par défaut).
    private static var defaultStoreURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent("default.store")
    }

    /// Construit le `ModelContainer` partagé, après migration éventuelle du store local.
    static func makeModelContainer() -> ModelContainer {
        migrerStoreSiNécessaire()
        let config = ModelConfiguration(url: sharedStoreURL)
        return try! ModelContainer(for: UserProfile.self, DailyGoal.self, HydrationLog.self,
                                   configurations: config)
    }

    /// Copie une seule fois le store local vers l'App Group si ce dernier n'existe pas encore.
    /// Idempotent : ne fait rien une fois le store partagé présent (ou si aucun store local).
    private static func migrerStoreSiNécessaire() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: sharedStoreURL.path),
              fm.fileExists(atPath: defaultStoreURL.path) else { return }
        // SQLite tient sur 3 fichiers : .store, -wal, -shm.
        for suffixe in ["", "-wal", "-shm"] {
            let src = URL(fileURLWithPath: defaultStoreURL.path + suffixe)
            let dst = URL(fileURLWithPath: sharedStoreURL.path + suffixe)
            if fm.fileExists(atPath: src.path) { try? fm.copyItem(at: src, to: dst) }
        }
    }
}
```

- [ ] **Step 2 : Brancher `WelloApp` sur la fabrique partagée**

Dans `Wello/Wello/App/WelloApp.swift`, remplacer la ligne 17 :

```swift
        let container = try! ModelContainer(for: UserProfile.self, DailyGoal.self, HydrationLog.self)
```

par :

```swift
        let container = WelloShared.makeModelContainer()
```

- [ ] **Step 3 : Type-check iOS**

Run la commande de type-check complète (voir `CLAUDE.md`).
Expected: `TYPECHECK_OK` (0 erreur). `WelloShared.swift` est pris par le glob `App/*.swift`.

- [ ] **Step 4 : Commit**

```bash
git add Wello/Wello/App/WelloShared.swift Wello/Wello/App/WelloApp.swift
git commit -m "feat(app): store SwiftData partagé via App Group + migration unique

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3 : Recharge des widgets après mutation (app)

Le store recharge les timelines après chaque changement du consommé/objectif, pour que les
widgets reflètent vite l'état quand l'app est active.

**Files:**
- Modify: `Wello/Wello/Services/HydrationStore.swift` (imports + `log`/`annulerDernièrePrise`/`supprimer`/`refreshToday` + helper privé)

- [ ] **Step 1 : Importer WidgetKit**

Dans `Wello/Wello/Services/HydrationStore.swift`, après `import WelloKit` (ligne 3), ajouter :

```swift
import WidgetKit
```

- [ ] **Step 2 : Ajouter le helper de recharge**

Dans `Wello/Wello/Services/HydrationStore.swift`, juste avant `private func upsertDailyGoal(` (ligne 326), insérer :

```swift
    /// Recharge toutes les timelines de widget : à appeler après tout changement du consommé
    /// ou de l'objectif du jour.
    private func rechargerWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }

```

- [ ] **Step 3 : Appeler la recharge après chaque mutation**

a) Dans `func log(...)`, après le bloc `if let objectif = breakdown?.totalML { ... }` (la dernière ligne de la fonction, juste avant son `}` de fermeture, ~ligne 226) ajouter :

```swift
        rechargerWidgets()
```

b) Idem à la fin de `func annulerDernièrePrise()` (après le bloc `if let objectif`, ~ligne 247).

```swift
        rechargerWidgets()
```

c) Idem à la fin de `func supprimer(_ log:)` (après le bloc `if let objectif`, ~ligne 260).

```swift
        rechargerWidgets()
```

d) Dans `func refreshToday(force:)`, après l'appel à `upsertDailyGoal(resultat)` (le `breakdown`/objectif du jour vient d'être recalculé), ajouter :

```swift
        rechargerWidgets()
```

> Repère : `upsertDailyGoal(resultat)` est appelé une seule fois dans `refreshToday`, juste après
> `breakdown = resultat`. Ajouter `rechargerWidgets()` sur la ligne suivante.

- [ ] **Step 4 : Type-check iOS**

Run la commande de type-check complète.
Expected: `TYPECHECK_OK` (0 erreur).

- [ ] **Step 5 : Commit**

```bash
git add Wello/Wello/Services/HydrationStore.swift
git commit -m "feat(app): recharge des widgets après chaque mutation du store

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4 : Extension widget — sources (cible Xcode)

Cette tâche fournit **toutes** les sources de l'extension. La création de la cible Xcode, les
capabilities App Group et la membership des fichiers sont des étapes manuelles (Task 5). Les
fichiers vivent dans `Wello/WelloWidget/`.

**Files:**
- Create: `Wello/WelloWidget/WelloWidgetBundle.swift`
- Create: `Wello/WelloWidget/AddWaterIntent.swift`
- Create: `Wello/WelloWidget/WelloWidget.swift`
- Create: `Wello/WelloWidget/WelloWidgetViews.swift`

- [ ] **Step 1 : Point d'entrée `WelloWidgetBundle.swift`**

Create `Wello/WelloWidget/WelloWidgetBundle.swift` :

```swift
import WidgetKit
import SwiftUI

/// Point d'entrée de l'extension widget : déclare le(s) widget(s) exposé(s).
@main
struct WelloWidgetBundle: WidgetBundle {
    var body: some Widget {
        WelloWidget()
    }
}
```

- [ ] **Step 2 : App Intent d'ajout rapide `AddWaterIntent.swift`**

Create `Wello/WelloWidget/AddWaterIntent.swift` :

```swift
import AppIntents
import SwiftData
import WidgetKit
import WelloKit

/// Ajoute une prise d'eau directement depuis le widget moyen, sans ouvrir l'app.
/// Insère un `HydrationLog` (eau, coefficient 1.0) dans le store partagé puis recharge les widgets.
struct AddWaterIntent: AppIntent {
    static var title: LocalizedStringResource = "Ajouter de l'eau"

    @Parameter(title: "Quantité (ml)")
    var amountML: Int

    init() {}
    init(amountML: Int) { self.amountML = amountML }

    func perform() async throws -> some IntentResult {
        let container = WelloShared.makeModelContainer()
        let ctx = ModelContext(container)
        ctx.insert(HydrationLog(amountML: amountML, source: "app",
                                drinkType: "water", coefficient: 1.0))
        try ctx.save()
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
```

- [ ] **Step 3 : `Widget` + `Provider` + `Entry` (`WelloWidget.swift`)**

Create `Wello/WelloWidget/WelloWidget.swift` :

```swift
import WidgetKit
import SwiftUI
import SwiftData
import WelloKit

/// Une lecture instantanée de l'hydratation du jour pour le widget.
struct WelloEntry: TimelineEntry {
    let date: Date
    let progress: WidgetProgress
    /// Montants des 3 boutons d'ajout rapide (repris du profil).
    let quickAdds: [Int]
    /// Faux tant qu'aucun `DailyGoal` n'existe (sexe non renseigné / objectif non calculé).
    let configuré: Bool

    static let placeholder = WelloEntry(
        date: .now,
        progress: WidgetProgress(consomméML: 1400, objectifML: 2300),
        quickAdds: [150, 250, 500], configuré: true)

    static let nonConfiguré = WelloEntry(
        date: .now, progress: WidgetProgress(consomméML: 0, objectifML: 0),
        quickAdds: [150, 250, 500], configuré: false)
}

/// Lit le store partagé et fournit la timeline. Recalculée à la demande (app/intent) et toutes
/// les ~15 min en filet de sécurité.
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> WelloEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (WelloEntry) -> Void) {
        completion(context.isPreview ? .placeholder : lireÉtat())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WelloEntry>) -> Void) {
        let entry = lireÉtat()
        let prochain = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(prochain)))
    }

    /// Lit l'objectif du jour et somme les prises du jour depuis le store partagé.
    private func lireÉtat() -> WelloEntry {
        let container = WelloShared.makeModelContainer()
        let ctx = ModelContext(container)
        let début = Calendar.current.startOfDay(for: .now)

        let logsDesc = FetchDescriptor<HydrationLog>(predicate: #Predicate { $0.loggedAt >= début })
        let consommé = ((try? ctx.fetch(logsDesc)) ?? []).reduce(0) { $0 + $1.effectiveML }

        let goalDesc = FetchDescriptor<DailyGoal>(predicate: #Predicate { $0.date == début })
        let goal = try? ctx.fetch(goalDesc).first

        let quick = ((try? ctx.fetch(FetchDescriptor<UserProfile>()))?.first)?.quickAdds ?? [150, 250, 500]

        return WelloEntry(
            date: .now,
            progress: WidgetProgress(consomméML: consommé, objectifML: goal?.totalML ?? 0),
            quickAdds: quick,
            configuré: goal != nil)
    }
}

/// Le widget Wello : petit + moyen (accueil) et accessoire circulaire (écran verrouillé).
struct WelloWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WelloWidget", provider: Provider()) { entry in
            WelloWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Hydratation")
        .description("Ta progression du jour, avec ajout rapide.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular])
    }
}
```

- [ ] **Step 4 : Vues des familles (`WelloWidgetViews.swift`)**

Create `Wello/WelloWidget/WelloWidgetViews.swift` :

```swift
import WidgetKit
import SwiftUI
import WelloKit

/// Teintes minimales du widget (dupliquées volontairement pour découpler l'extension du thème app).
private enum WidgetTheme {
    static let accent = Color(red: 0.31, green: 0.69, blue: 0.90)      // 0x4FB0E5
    static let accentDeep = Color(red: 0.18, green: 0.55, blue: 0.79)  // 0x2E8BC9
    static let gradient = LinearGradient(colors: [accent, accentDeep],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// Aiguille selon la famille de widget.
struct WelloWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WelloEntry

    var body: some View {
        switch family {
        case .accessoryCircular: AccessoryView(entry: entry)
        case .systemMedium:      MediumView(entry: entry)
        default:                 SmallView(entry: entry)
        }
    }
}

/// Anneau de progression réutilisable.
private struct Ring: View {
    let fraction: Double
    var lineWidth: CGFloat = 10
    var body: some View {
        ZStack {
            Circle().stroke(WidgetTheme.accent.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, fraction))
                .stroke(WidgetTheme.gradient,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

/// Petit widget (accueil) : anneau + valeurs. Affichage seul.
private struct SmallView: View {
    let entry: WelloEntry
    var body: some View {
        if entry.configuré {
            VStack(spacing: 8) {
                ZStack {
                    Ring(fraction: entry.progress.fraction)
                    Text(entry.progress.libelléPourcent)
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(WidgetTheme.accentDeep)
                }
                Text(entry.progress.libelléValeurs)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(4)
        } else {
            NonConfiguré()
        }
    }
}

/// Widget moyen (accueil) : valeurs + barre + 3 boutons d'ajout rapide (interactif).
private struct MediumView: View {
    let entry: WelloEntry
    var body: some View {
        if entry.configuré {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Wello", systemImage: "drop.fill")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(WidgetTheme.accentDeep)
                    Spacer()
                    Text("\(entry.progress.libelléValeurs) · \(entry.progress.libelléPourcent)")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: entry.progress.fraction)
                    .tint(WidgetTheme.accent)
                HStack(spacing: 8) {
                    ForEach(entry.quickAdds, id: \.self) { ml in
                        Button(intent: AddWaterIntent(amountML: ml)) {
                            Text("+\(ml)")
                                .font(.system(.subheadline, design: .rounded).weight(.bold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(WidgetTheme.accent)
                    }
                }
            }
            .padding(4)
        } else {
            NonConfiguré()
        }
    }
}

/// Accessoire écran verrouillé : anneau teinté + pourcent. Affichage seul.
private struct AccessoryView: View {
    let entry: WelloEntry
    var body: some View {
        Gauge(value: entry.configuré ? entry.progress.fraction : 0) {
            Image(systemName: "drop.fill")
        } currentValueLabel: {
            Text(entry.configuré ? entry.progress.libelléPourcent : "—")
        }
        .gaugeStyle(.accessoryCircular)
    }
}

/// État « pas encore configuré » (sexe non renseigné / objectif non calculé).
private struct NonConfiguré: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "drop")
                .font(.title2)
                .foregroundStyle(WidgetTheme.accent)
            Text("Ouvre Wello")
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

#if DEBUG
#Preview("Petit", as: .systemSmall) { WelloWidget() } timeline: { WelloEntry.placeholder }
#Preview("Moyen", as: .systemMedium) { WelloWidget() } timeline: { WelloEntry.placeholder }
#Preview("Accessoire", as: .accessoryCircular) { WelloWidget() } timeline: { WelloEntry.placeholder }
#endif
```

- [ ] **Step 5 : Type-check best-effort de l'extension (non bloquant)**

> WidgetKit/AppIntents sont dans le SDK simulateur ; ce type-check peut passer hors Xcode, mais la
> cible widget n'existe pas encore — c'est **indicatif**. L'autorité reste la preview Xcode (Task 5).
> Il faut compiler les sources widget **avec** `WelloShared.swift` et les 3 `@Model` (partagés).

```bash
rm -rf /tmp/wellomod && mkdir -p /tmp/wellomod
xcrun --sdk iphonesimulator swiftc -emit-module -module-name WelloKit \
  -target arm64-apple-ios17.0-simulator \
  WelloKit/Sources/WelloKit/*.swift WelloKit/Sources/WelloKit/Models/*.swift \
  -emit-module-path /tmp/wellomod/WelloKit.swiftmodule
xcrun --sdk iphonesimulator swiftc -typecheck -D DEBUG \
  -enable-upcoming-feature MemberImportVisibility \
  -target arm64-apple-ios17.0-simulator -I /tmp/wellomod \
  Wello/Wello/Models/*.swift Wello/Wello/App/WelloShared.swift \
  Wello/WelloWidget/*.swift && echo WIDGET_TYPECHECK_OK
```

Expected (idéal) : `WIDGET_TYPECHECK_OK`. Si des erreurs apparaissent uniquement liées à l'absence
de cible/`@main`/macros, les noter pour validation Xcode ; toute erreur de signature
(`AddWaterIntent`, `WidgetProgress`, modèles) doit être corrigée ici.

- [ ] **Step 6 : Commit**

```bash
git add Wello/WelloWidget/
git commit -m "feat(widget): extension WidgetKit — petit/moyen/accessoire + AppIntent d'ajout

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5 : Intégration Xcode + documentation

Étapes manuelles dans Xcode (non automatisables en CLI) puis docs.

**Files:**
- Modify: `README.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1 : Créer la cible widget dans Xcode (manuel)**

1. File ▸ New ▸ Target ▸ **Widget Extension**, nom **WelloWidget**, *Include Configuration Intent* **décoché**, *Include Live Activity* **décoché**.
2. Supprimer le fichier d'exemple généré ; **ajouter** à la cible les 4 fichiers de `Wello/WelloWidget/`.
3. Ajouter à la **membership de la cible WelloWidget** : `Wello/Wello/Models/UserProfile.swift`, `DailyGoal.swift`, `HydrationLog.swift`, et `Wello/Wello/App/WelloShared.swift`.
4. Lier le package **WelloKit** à la cible WelloWidget (Frameworks and Libraries).
5. Déploiement minimum de la cible widget : **iOS 17.0**.

- [ ] **Step 2 : Capability App Group (manuel)**

Sur **la cible app** *et* **la cible WelloWidget** : Signing & Capabilities ▸ + Capability ▸ **App Groups** ▸ ajouter **`group.Life.Wello`** (coché sur les deux).

- [ ] **Step 3 : Preview & test sur simulateur (manuel)**

1. Sélectionner le schéma **WelloWidget** ▸ preview des 3 familles (petit / moyen / accessoire).
2. Lancer l'app, enregistrer quelques prises, ajouter les widgets à l'écran d'accueil + verrouillé.
3. Depuis le **widget moyen**, taper **+250** → la prise est persistée (la vérifier dans l'app au `foreground`), et l'anneau se met à jour.
4. **Migration** : installer d'abord une build **pré-widget** (store local peuplé), puis la build widget → vérifier que l'historique est conservé.

- [ ] **Step 4 : `README` — Phase 2 / widget**

Dans `README.md`, remplacer le paragraphe « Hors périmètre (Phase 1) » concernant le Widget par une
note indiquant que le **Widget iOS est livré** (petit/moyen/accessoire, ajout rapide via App Intents,
partage via App Group `group.Life.Wello`), watchOS restant en Phase 2. Texte à insérer :

```
## Widget iOS (Phase 2 — livré)

Widgets d'écran d'accueil (petit : anneau d'objectif ; moyen : barre + boutons d'ajout rapide
+150/+250/+500) et accessoire d'écran verrouillé (anneau). Partage de données app↔widget via
l'App Group `group.Life.Wello` (store SwiftData unique, migré depuis le store local au premier
lancement). L'ajout rapide écrit une prise sans ouvrir l'app (App Intents, iOS 17).
watchOS / complication Watch restent prévus en Phase 2.
```

- [ ] **Step 5 : `CLAUDE.md` — carte projet + étapes Xcode**

Dans `CLAUDE.md` :

a) Ajouter sous la « Carte du projet » une entrée :

```
- `Wello/WelloWidget/` — extension WidgetKit (Phase 2) : `Provider` lisant le store partagé,
  vues des familles, `AddWaterIntent`. Partage le store via App Group `group.Life.Wello`.
```

b) Dans « Étapes Xcode manuelles », ajouter :

```
Cible WidgetExtension `WelloWidget` : membership des 3 `@Model` + `WelloShared.swift`, lien WelloKit,
capability App Group `group.Life.Wello` sur l'app ET l'extension.
```

- [ ] **Step 6 : Vérification finale**

```bash
cd WelloKit && swift test && cd ..
```
Expected: tout vert. Puis la commande de type-check **app** complète (`CLAUDE.md`) → `TYPECHECK_OK`.

- [ ] **Step 7 : Commit**

```bash
git add README.md CLAUDE.md
git commit -m "docs: widget iOS Phase 2 (App Group, familles, étapes Xcode)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Vérification finale

- [ ] `cd WelloKit && swift test` → vert (`WidgetProgress` ajouté, suite complète OK).
- [ ] Type-check iOS **app** complet → `TYPECHECK_OK`.
- [ ] (Best-effort) type-check des sources widget → pas d'erreur de signature.
- [ ] Xcode (manuel) : 3 familles en preview ; ajout +250 depuis le moyen persiste une prise ;
  écran verrouillé montre l'anneau ; migration conserve l'historique.

## Self-Review (effectuée)

**Couverture de la spec :**
- Partage store App Group + migration → Task 2 ✅
- `WidgetProgress` pur testé CLI → Task 1 ✅
- Petit (anneau) / moyen (boutons) / accessoryCircular → Task 4 (vues + familles) ✅
- `AddWaterIntent` (écriture + reload) → Task 4 ✅
- Reload déclenché par l'app après mutation → Task 3 ✅
- Cas non configuré / négatif / dépassement → Task 1 (calcul) + Task 4 (`NonConfiguré`) ✅
- Identité (App Group, bundle, membership, lien WelloKit) → Task 5 (étapes Xcode) ✅
- Docs README + CLAUDE.md → Task 5 ✅
- Hors périmètre (large, choix boisson, configurable, watchOS) : non implémentés ✅

**Placeholders :** aucun — chaque étape contient le code/texte réel.

**Cohérence des types :** `WidgetProgress(consomméML:objectifML:)` + `.fraction`/`.pourcent`/
`.libelléValeurs`/`.libelléPourcent`/`.consomméLitres`/`.objectifLitres` (Task 1) utilisés dans
les vues (Task 4) ; `WelloShared.makeModelContainer()` (Task 2) utilisé par `WelloApp` (Task 2),
`Provider` et `AddWaterIntent` (Task 4) ; `AddWaterIntent(amountML:)` défini Task 4 et appelé dans
`MediumView` ; `WelloEntry` (champs `progress`/`quickAdds`/`configuré`) cohérent entre `Provider`,
les vues et les previews ; `HydrationLog(amountML:source:drinkType:coefficient:)` conforme au
modèle existant.
```
