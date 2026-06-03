import SwiftUI
import WelloKit

/// Carte détaillant la composition de l'objectif du jour.
struct BreakdownCard: View {
    let breakdown: GoalBreakdown
    /// Vrai si la météo n'a pas pu être récupérée (le bonus à 0 n'est alors pas significatif).
    var météoIndisponible: Bool = false

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 14) {
                Text("Détail de l'objectif")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(WelloTheme.ink)

                ligne("Base (poids)", breakdown.baseML, icon: "scalemass.fill", teinte: WelloTheme.accent)
                ligne("Activité", breakdown.activityBonusML, icon: "figure.run", teinte: .orange)
                ligne("Météo", breakdown.weatherBonusML, icon: "cloud.sun.fill", teinte: .yellow)
                ligne("Plancher médical", breakdown.medicalFloorML, icon: "cross.case.fill", teinte: .pink)

                Divider().overlay(WelloTheme.inkSoft.opacity(0.25))

                HStack {
                    Text("Total")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(WelloTheme.ink)
                    Spacer()
                    Text("\(breakdown.totalML) ml")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(WelloTheme.accentDeep)
                }

                if météoIndisponible {
                    badge("Météo indisponible — bonus non appliqué", "wifi.slash", .gray)
                }
                if breakdown.plancherContraignant {
                    badge("Objectif relevé au plancher médical", "cross.case.fill", .pink)
                }
                if breakdown.plafondAppliqué {
                    badge("Bridé au plafond de sécurité (4000 ml)", "exclamationmark.shield.fill", .orange)
                }
            }
        }
    }

    private func ligne(_ libellé: String, _ valeur: Int, icon: String, teinte: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(teinte)
                .frame(width: 30, height: 30)
                .background(teinte.opacity(0.15), in: Circle())
            Text(libellé)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(WelloTheme.inkSoft)
            Spacer()
            Text("\(valeur) ml")
                .font(.system(.body, design: .rounded).weight(.medium))
                .foregroundStyle(WelloTheme.ink)
        }
    }

    private func badge(_ texte: String, _ icon: String, _ teinte: Color) -> some View {
        Label(texte, systemImage: icon)
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(teinte)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(teinte.opacity(0.12), in: Capsule())
    }
}

#if DEBUG
#Preview {
    BreakdownCard(breakdown: GoalBreakdown(baseML: 2730, activityBonusML: 300, weatherBonusML: 500,
                                           medicalFloorML: 2500, totalML: 3530,
                                           plancherContraignant: false, plafondAppliqué: false))
    .padding()
    .welloBackground()
}
#endif
