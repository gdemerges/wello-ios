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
                Text(pourcent(context.state.progression))
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
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
