import WidgetKit
import SwiftUI
import WelloKit

/// Une lecture instantanée de l'hydratation du jour pour la complication de cadran.
struct WelloComplicationEntry: TimelineEntry {
    let date: Date
    let progress: WidgetProgress
    /// Faux tant que la Watch n'a jamais reçu d'objectif configuré de l'iPhone.
    let configuré: Bool

    static let placeholder = WelloComplicationEntry(
        date: .now,
        progress: WidgetProgress(consomméML: 1400, objectifML: 2300),
        configuré: true)

    static let nonConfiguré = WelloComplicationEntry(
        date: .now, progress: WidgetProgress(consomméML: 0, objectifML: 0), configuré: false)
}

/// Lit le dernier état publié par l'app Watch (App Group local à la montre). Rafraîchie à la
/// demande (`WidgetCenter.reloadAllTimelines` depuis le `WatchStore`) et toutes les ~30 min en
/// filet de sécurité.
struct ComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> WelloComplicationEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (WelloComplicationEntry) -> Void) {
        completion(context.isPreview ? .placeholder : lire())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WelloComplicationEntry>) -> Void) {
        let prochain = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
        completion(Timeline(entries: [lire()], policy: .after(prochain)))
    }

    private func lire() -> WelloComplicationEntry {
        let (progress, configuré) = WelloWatchShared.lire()
        return WelloComplicationEntry(date: .now, progress: progress, configuré: configuré)
    }
}

/// Aiguille selon la famille de complication.
struct WelloComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WelloComplicationEntry

    var body: some View {
        switch family {
        case .accessoryCorner:      CornerView(entry: entry)
        case .accessoryRectangular: RectangularView(entry: entry)
        case .accessoryInline:      InlineView(entry: entry)
        default:                    CircularView(entry: entry)
        }
    }
}

/// Circulaire : jauge teintée + pourcent.
private struct CircularView: View {
    let entry: WelloComplicationEntry
    var body: some View {
        Gauge(value: entry.configuré ? entry.progress.fraction : 0) {
            Image(systemName: "drop.fill")
        } currentValueLabel: {
            Text(entry.configuré ? entry.progress.libelléPourcent : "—")
        }
        .gaugeStyle(.accessoryCircular)
    }
}

/// Coin de cadran : jauge circulaire + libellé courbé.
private struct CornerView: View {
    let entry: WelloComplicationEntry
    var body: some View {
        Gauge(value: entry.configuré ? entry.progress.fraction : 0) {
            Image(systemName: "drop.fill")
        }
        .gaugeStyle(.accessoryCircular)
        .widgetLabel(entry.configuré ? entry.progress.libelléPourcent : "Wello")
    }
}

/// Rectangulaire : titre + valeurs + barre de progression.
private struct RectangularView: View {
    let entry: WelloComplicationEntry
    var body: some View {
        if entry.configuré {
            VStack(alignment: .leading, spacing: 2) {
                Label("Hydratation", systemImage: "drop.fill")
                    .font(.headline)
                Gauge(value: entry.progress.fraction) {
                    EmptyView()
                } currentValueLabel: {
                    Text("\(entry.progress.libelléValeurs) · \(entry.progress.libelléPourcent)")
                }
                .gaugeStyle(.accessoryLinearCapacity)
            }
            .widgetAccentable()
        } else {
            Label("Ouvre Wello", systemImage: "drop")
                .font(.headline)
        }
    }
}

/// En ligne (au-dessus de l'heure) : une seule ligne texte + icône.
private struct InlineView: View {
    let entry: WelloComplicationEntry
    var body: some View {
        if entry.configuré {
            Label("\(entry.progress.libelléValeurs) · \(entry.progress.libelléPourcent)",
                  systemImage: "drop.fill")
        } else {
            Label("Ouvre Wello", systemImage: "drop")
        }
    }
}

/// Complication de cadran Wello : circulaire, coin, en ligne, rectangulaire.
struct WelloComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WelloComplication", provider: ComplicationProvider()) { entry in
            WelloComplicationView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Hydratation")
        .description("Ta progression du jour sur le cadran.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner,
                            .accessoryInline, .accessoryRectangular])
    }
}

#if DEBUG
#Preview("Circulaire", as: .accessoryCircular) { WelloComplication() } timeline: { WelloComplicationEntry.placeholder }
#Preview("Coin", as: .accessoryCorner) { WelloComplication() } timeline: { WelloComplicationEntry.placeholder }
#Preview("En ligne", as: .accessoryInline) { WelloComplication() } timeline: { WelloComplicationEntry.placeholder }
#Preview("Rectangulaire", as: .accessoryRectangular) { WelloComplication() } timeline: { WelloComplicationEntry.placeholder }
#endif
