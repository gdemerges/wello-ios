import AppIntents
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
