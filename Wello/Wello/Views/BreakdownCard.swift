import SwiftUI
import WelloKit

/// Carte détaillant la composition de l'objectif du jour (100 % additif).
struct BreakdownCard: View {
    let breakdown: GoalBreakdown
    /// Vrai si la météo n'a pas pu être récupérée (le bonus à 0 n'est alors pas significatif).
    var météoIndisponible: Bool = false
    /// Libellé de la ligne état physiologique (selon l'état actif). nil si aucun.
    var libelléÉtatPhysio: String? = nil

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 14) {
                Text("Détail de l'objectif")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(WelloTheme.ink)

                // Termes additifs : base + bonus, dans l'ordre. Optionnels masqués si nuls.
                ligne("Base (EFSA)", breakdown.baseML, icon: "person.fill", teinte: WelloTheme.accent)
                ligne("Activité", breakdown.activityBonusML, icon: "figure.run", teinte: .orange, signe: "+")
                ligne("Météo", breakdown.weatherBonusML, icon: "cloud.sun.fill", teinte: .yellow, signe: "+")
                if breakdown.lifeStageBonusML > 0 {
                    ligne(libelléÉtatPhysio ?? "État physiologique", breakdown.lifeStageBonusML,
                          icon: "figure.stand", teinte: .pink, signe: "+")
                }
                if breakdown.renalBonusML > 0 {
                    ligne("Besoin rénal", breakdown.renalBonusML,
                          icon: "cross.case.fill", teinte: .purple, signe: "+")
                }
                if breakdown.manualAdjustmentML != 0 {
                    // Valeur négative : le "-" est déjà porté par l'entier.
                    ligne("Réglage avancé", breakdown.manualAdjustmentML,
                          icon: "slider.horizontal.3", teinte: WelloTheme.accentDeep,
                          signe: breakdown.manualAdjustmentML > 0 ? "+" : "")
                }

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
                if breakdown.plafondAppliqué {
                    badge("Bridé au plafond de sécurité (4000 ml)", "exclamationmark.shield.fill", .orange)
                }
            }
        }
    }

    private func ligne(_ libellé: String, _ valeur: Int, icon: String, teinte: Color,
                       signe: String = "") -> some View {
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
            Text("\(signe)\(valeur) ml")
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
    BreakdownCard(breakdown: GoalBreakdown(baseML: 1600, activityBonusML: 200, weatherBonusML: 300,
                                           lifeStageBonusML: 700, renalBonusML: 0, totalML: 2800,
                                           plafondAppliqué: false),
                  libelléÉtatPhysio: "Allaitement")
    .padding()
    .welloBackground()
}
#endif
