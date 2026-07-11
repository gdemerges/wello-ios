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
        let consommé = clampedDayTotal(((try? ctx.fetch(logsDesc)) ?? []).reduce(0) { $0 + $1.effectiveML })

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

/// Le widget Wello : petit + moyen (accueil) et accessoires écran verrouillé
/// (circulaire, rectangulaire, en ligne).
struct WelloWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WelloWidget", provider: Provider()) { entry in
            WelloWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Hydratation")
        .description("Ta progression du jour, avec ajout rapide.")
        .supportedFamilies([.systemSmall, .systemMedium,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
