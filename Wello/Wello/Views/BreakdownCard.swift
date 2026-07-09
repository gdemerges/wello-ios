import SwiftUI
import WelloKit

/// Carte détaillant la composition de l'objectif du jour (100 % additif).
/// Chaque ligne est tappable : elle ouvre l'explication sourcée de la composante (« Méthode »).
struct BreakdownCard: View {
    let breakdown: GoalBreakdown
    /// Vrai si la météo n'a pas pu être récupérée (le bonus à 0 n'est alors pas significatif).
    var météoIndisponible: Bool = false
    /// Libellé de la ligne état physiologique (selon l'état actif). nil si aucun.
    var libelléÉtatPhysio: String? = nil

    /// Composante dont l'explication est affichée en feuille (nil = aucune).
    @State private var détail: Composante?
    /// Présente l'écran « Méthode » complet.
    @State private var méthode = false

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 14) {
                Text("Détail de l'objectif")
                    .font(.welloEntête)
                    .foregroundStyle(WelloTheme.ink)

                // Termes additifs : base + bonus, dans l'ordre. Optionnels masqués si nuls.
                ligne(.base, "Base (EFSA)", breakdown.baseML)
                ligne(.activité, "Activité", breakdown.activityBonusML, signe: "+")
                ligne(.météo, "Météo", breakdown.weatherBonusML, signe: "+")
                if breakdown.altitudeBonusML > 0 {
                    ligne(.altitude, "Altitude", breakdown.altitudeBonusML, signe: "+")
                }
                if breakdown.lifeStageBonusML > 0 {
                    ligne(.physiologie, libelléÉtatPhysioKey, breakdown.lifeStageBonusML, signe: "+")
                }
                if breakdown.renalBonusML > 0 {
                    ligne(.rénal, "Besoin rénal", breakdown.renalBonusML, signe: "+")
                }
                if breakdown.bodyBonusML != 0 {
                    // Valeur négative : le "-" est déjà porté par l'entier.
                    ligne(.corpulence, "Corpulence", breakdown.bodyBonusML,
                          signe: breakdown.bodyBonusML > 0 ? "+" : "")
                }
                if breakdown.manualAdjustmentML != 0 {
                    ligne(.réglage, "Réglage avancé", breakdown.manualAdjustmentML,
                          signe: breakdown.manualAdjustmentML > 0 ? "+" : "")
                }

                Divider().overlay(WelloTheme.inkSoft.opacity(0.25))

                HStack {
                    Text("Total")
                        .font(.welloEntête)
                        .foregroundStyle(WelloTheme.ink)
                    Spacer()
                    Text("\(breakdown.totalML) ml")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(WelloTheme.accentDeep)
                }
                .accessibilityElement(children: .combine)

                if météoIndisponible {
                    badge("Météo indisponible — bonus non appliqué", "wifi.slash", .gray)
                }
                if breakdown.plafondAppliqué {
                    badge("Bridé au plafond de sécurité (4000 ml)", "exclamationmark.shield.fill", .orange)
                }

                Button {
                    méthode = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                        Text("Comment mon objectif est-il calculé ?")
                    }
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .foregroundStyle(WelloTheme.accentDeep)
                    .frame(minHeight: 44)
                }
                .accessibilityHint("Ouvre l'explication détaillée du calcul")
            }
        }
        .sheet(item: $détail) { ComposanteDetailView(composante: $0) }
        .sheet(isPresented: $méthode) { MéthodeView() }
    }

    /// Libellé de la ligne physio en `LocalizedStringKey` (l'état actif, ou un défaut générique).
    private var libelléÉtatPhysioKey: LocalizedStringKey {
        libelléÉtatPhysio.map { LocalizedStringKey($0) } ?? "État physiologique"
    }

    /// Une ligne du breakdown, tappable → ouvre l'explication sourcée de la composante.
    /// Icône et teinte proviennent de la composante (cohérence avec la feuille de détail).
    private func ligne(_ composante: Composante, _ libellé: LocalizedStringKey, _ valeur: Int,
                       signe: String = "") -> some View {
        Button {
            détail = composante
        } label: {
            HStack(spacing: 12) {
                Image(systemName: composante.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(composante.teinte)
                    .frame(width: 30, height: 30)
                    .background(composante.teinte.opacity(0.15), in: Circle())
                Text(libellé)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(WelloTheme.inkSoft)
                Spacer()
                Text("\(signe)\(valeur) ml")
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .foregroundStyle(WelloTheme.ink)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WelloTheme.inkSoft.opacity(0.4))
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Un seul élément VoiceOver par ligne : « Base (EFSA), +200 ml » plutôt que deux swipes.
        .accessibilityElement(children: .combine)
        .accessibilityHint("Voir l'explication")
    }

    private func badge(_ texte: LocalizedStringKey, _ icon: String, _ teinte: Color) -> some View {
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
                                           altitudeBonusML: 150, lifeStageBonusML: 700, renalBonusML: 0,
                                           bodyBonusML: 200, totalML: 3150,
                                           plafondAppliqué: false),
                  libelléÉtatPhysio: "Allaitement")
    .padding()
    .welloBackground()
}
#endif
