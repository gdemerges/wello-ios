import ActivityKit
import WidgetKit
import SwiftUI

/// Live Activity d'hydratation : progression du jour sur l'écran verrouillé et dans la
/// Dynamic Island. Rendue par l'extension widget, alimentée par l'app via `LiveActivityManager`.
struct HydrationLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HydrationActivityAttributes.self) { context in
            écranVerrouillé(context.state)
                .padding()
                .activityBackgroundTint(Color.black.opacity(0.35))
                .activitySystemActionForegroundColor(.cyan)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("\(context.state.consomméML) ml", systemImage: "drop.fill")
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundStyle(.cyan)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Objectif \(context.state.objectifML) ml")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(value: context.state.progression)
                        .tint(.cyan)
                        .accessibilityLabel("Hydratation du jour")
                        .accessibilityValue("\(pourcent(context.state.progression))")
                }
            } compactLeading: {
                Image(systemName: context.state.atteint ? "checkmark.seal.fill" : "drop.fill")
                    .foregroundStyle(.cyan)
            } compactTrailing: {
                // iOS 27 : la Dynamic Island compacte/minimale est désormais visible en paysage
                // (largeur réduite) en plus du portrait — on y abandonne le pourcentage pour la goutte
                // seule, comme en `minimal`, plutôt que de tronquer le texte. Cible min. iOS 18 :
                // repli sur le pourcentage fixe tant que l'environnement n'existe pas.
                if #available(iOS 27.0, *) {
                    CompactTrailing(progression: context.state.progression)
                } else {
                    Text(pourcent(context.state.progression))
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                }
            } minimal: {
                Image(systemName: "drop.fill").foregroundStyle(.cyan)
            }
            .keylineTint(.cyan)
        }
    }

    /// Vue de l'écran verrouillé / bannière.
    private func écranVerrouillé(_ s: HydrationActivityAttributes.ContentState) -> some View {
        HStack(spacing: 14) {
            Image(systemName: s.atteint ? "checkmark.seal.fill" : "drop.fill")
                .font(.system(size: 30))
                .foregroundStyle(.cyan)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(s.atteint ? "Objectif atteint 🎉" : "Hydratation du jour")
                    .font(.system(.headline, design: .rounded))
                Text("\(s.consomméML) / \(s.objectifML) ml")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                ProgressView(value: s.progression).tint(.cyan)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(s.atteint
            ? "Objectif d'hydratation atteint : \(s.consomméML) sur \(s.objectifML) millilitres"
            : "Hydratation du jour : \(s.consomméML) sur \(s.objectifML) millilitres, \(pourcent(s.progression))")
    }

    private func pourcent(_ p: Double) -> String { "\(Int((p * 100).rounded()))%" }
}

/// Isole la lecture d'`isDynamicIslandLimitedInWidth` (iOS 27+) : `DynamicIsland` construit ses
/// fermetures hors contexte de vue, l'`@Environment` doit donc vivre dans une sous-vue dédiée.
@available(iOS 27.0, *)
private struct CompactTrailing: View {
    let progression: Double
    @Environment(\.isDynamicIslandLimitedInWidth) private var largeurLimitée

    var body: some View {
        if largeurLimitée {
            Image(systemName: "drop.fill").foregroundStyle(.cyan)
        } else {
            Text("\(Int((progression * 100).rounded()))%")
                .font(.system(.caption2, design: .rounded).weight(.semibold))
        }
    }
}
