import SwiftUI
import WelloKit

/// Carte détaillant la composition de l'objectif du jour.
struct BreakdownCard: View {
    let breakdown: GoalBreakdown
    /// Vrai si la météo n'a pas pu être récupérée (le bonus à 0 n'est alors pas significatif).
    var météoIndisponible: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Détail de l'objectif")
                .font(.headline)
            ligne("Base (poids)", breakdown.baseML)
            ligne("Activité", breakdown.activityBonusML)
            ligne("Météo", breakdown.weatherBonusML)
            ligne("Plancher médical", breakdown.medicalFloorML)
            Divider()
            HStack {
                Text("Total").fontWeight(.semibold)
                Spacer()
                Text("\(breakdown.totalML) ml").fontWeight(.semibold)
            }
            if météoIndisponible {
                badge("Météo indisponible — bonus non appliqué", systemImage: "wifi.slash")
            }
            if breakdown.plancherContraignant {
                badge("Objectif relevé au plancher médical", systemImage: "cross.case")
            }
            if breakdown.plafondAppliqué {
                badge("Bridé au plafond de sécurité (4000 ml)", systemImage: "exclamationmark.shield")
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func ligne(_ libellé: String, _ valeur: Int) -> some View {
        HStack {
            Text(libellé).foregroundStyle(.secondary)
            Spacer()
            Text("\(valeur) ml")
        }
    }

    private func badge(_ texte: String, systemImage: String) -> some View {
        Label(texte, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(.orange)
            .padding(.top, 4)
    }
}

#Preview {
    BreakdownCard(breakdown: GoalBreakdown(baseML: 2450, activityBonusML: 500, weatherBonusML: 300,
                                           medicalFloorML: 2500, totalML: 3250,
                                           plancherContraignant: false, plafondAppliqué: false))
    .padding()
}
