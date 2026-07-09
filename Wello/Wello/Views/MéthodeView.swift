import SwiftUI

/// Une composante explicable de l'objectif : sa justification et sa source scientifique.
/// Partagé entre l'écran « Méthode » (liste complète) et la carte de détail (composante tappée
/// depuis `BreakdownCard`). Textes en `LocalizedStringKey` → extraits dans le String Catalog.
enum Composante: String, CaseIterable, Identifiable {
    case base, activité, météo, altitude, physiologie, rénal, corpulence, réglage, sécurité

    var id: String { rawValue }

    var titre: LocalizedStringKey {
        switch self {
        case .base: return "Base (EFSA)"
        case .activité: return "Activité"
        case .météo: return "Météo"
        case .altitude: return "Altitude"
        case .physiologie: return "État physiologique"
        case .rénal: return "Besoin rénal"
        case .corpulence: return "Corpulence"
        case .réglage: return "Réglage avancé"
        case .sécurité: return "Plafond de sécurité"
        }
    }

    var icon: String {
        switch self {
        case .base: return "person.fill"
        case .activité: return "figure.run"
        case .météo: return "cloud.sun.fill"
        case .altitude: return "mountain.2.fill"
        case .physiologie: return "figure.stand"
        case .rénal: return "cross.case.fill"
        case .corpulence: return "scalemass.fill"
        case .réglage: return "slider.horizontal.3"
        case .sécurité: return "exclamationmark.shield.fill"
        }
    }

    var teinte: Color {
        switch self {
        case .base: return WelloTheme.accent
        case .activité: return .orange
        case .météo: return .yellow
        case .altitude: return .teal
        case .physiologie: return .pink
        case .rénal: return .purple
        case .corpulence: return .indigo
        case .réglage: return WelloTheme.accentDeep
        case .sécurité: return .orange
        }
    }

    var explication: LocalizedStringKey {
        switch self {
        case .base:
            return "La base part des apports de référence européens : environ 2 L de boisson par jour pour un homme, 1,6 L pour une femme. Ils couvrent ~80 % de l'eau totale — le reste vient des aliments. On ne part pas du poids (× 35 ml/kg), qui estime l'eau totale et surévalue la cible de boisson."
        case .activité:
            return "Chaque kilocalorie dépensée à l'effort ajoute environ 1 ml. Évaporer 1 ml de sueur dissipe ~0,58 kcal, et l'essentiel de l'énergie d'un exercice se transforme en chaleur évacuée par la sueur. On part de l'énergie active (intensité réelle), pas de la seule durée."
        case .météo:
            return "Le bonus suit la température *ressentie*, pas la seule température affichée : elle intègre humidité, vent et rayonnement. Un 30 °C sec (la sueur s'évapore) et un 30 °C humide (elle ne s'évapore plus) n'imposent pas le même effort. +50 ml par °C au-dessus de 27 °C."
        case .altitude:
            return "En altitude, l'air plus sec et une respiration accrue augmentent les pertes en eau, et la diurèse d'adaptation s'élève. On ajoute +150 ml par tranche de 1000 m au-dessus de 2000 m."
        case .physiologie:
            return "La grossesse (+300 ml) et l'allaitement (+700 ml) élèvent les besoins hydriques, conformément aux apports de référence EFSA."
        case .rénal:
            return "En prévention des calculs rénaux (lithiase), maintenir une diurèse abondante est recommandé. Le supplément est réglable et doit être ajusté avec ton médecin."
        case .corpulence:
            return "Une corpulence plus élevée s'accompagne d'un volume hydrique corporel plus grand. On ajuste modérément la base selon ton poids (au maximum ±400 ml), sans basculer vers un calcul au kilo qui surestimerait la cible."
        case .réglage:
            return "Tu peux affiner manuellement ta sensibilité à l'effort et à la chaleur, ou appliquer un décalage fixe. Les plafonds de sécurité restent toujours appliqués."
        case .sécurité:
            return "L'objectif est plafonné à 4000 ml par jour. Au-delà, boire plus n'apporte rien et peut devenir risqué (hyponatrémie). Ce plafond n'est jamais dépassé, quels que soient les réglages."
        }
    }

    var source: LocalizedStringKey {
        switch self {
        case .base: return "Source : EFSA 2010 — apports de référence en eau."
        case .activité: return "Fondé sur la thermodynamique de la sudation. Plafonné à 1000 ml."
        case .météo: return "Température apparente (Open-Meteo). Plafonné à 600 ml."
        case .altitude: return "Altitude fournie par Open-Meteo. Plafonné à 500 ml."
        case .physiologie: return "Source : EFSA 2010."
        case .rénal: return "À personnaliser selon avis médical."
        case .corpulence: return "Ajustement borné à ±400 ml. Inclus dans Wello+."
        case .réglage: return "Réglage avancé, inclus dans Wello+."
        case .sécurité: return "Garde-fou anti-hyperhydratation."
        }
    }
}

/// Carte de détail d'une composante (présentée en feuille quand on tape une ligne du breakdown).
struct ComposanteDetailView: View {
    let composante: Composante
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 14) {
                        Image(systemName: composante.icon)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(composante.teinte)
                            .frame(width: 48, height: 48)
                            .background(composante.teinte.opacity(0.15), in: Circle())
                            .accessibilityHidden(true)
                        Text(composante.titre)
                            .font(.welloTitre)
                            .foregroundStyle(WelloTheme.ink)
                    }
                    Text(composante.explication)
                        .font(.welloProse)
                        .foregroundStyle(WelloTheme.ink)
                    Text(composante.source)
                        .font(.welloLégende)
                        .foregroundStyle(WelloTheme.inkSoft)
                    Spacer(minLength: 0)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .welloBackground()
            .navigationTitle("Détail du calcul")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Écran « Méthode » : explique de façon transparente et sourcée comment l'objectif est calculé.
/// Argument de confiance (et de différenciation) : la rigueur du calcul devient visible.
struct MéthodeView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Ton objectif n'est pas un chiffre magique : c'est une somme de termes, chacun fondé sur des données publiées. Voici lesquels, et pourquoi.")
                        .font(.welloProseDouce)
                        .foregroundStyle(WelloTheme.inkSoft)
                        .padding(.horizontal, 4)

                    ForEach(Composante.allCases) { c in
                        CardContainer {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 12) {
                                    Image(systemName: c.icon)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(c.teinte)
                                        .frame(width: 34, height: 34)
                                        .background(c.teinte.opacity(0.15), in: Circle())
                                        .accessibilityHidden(true)
                                    Text(c.titre)
                                        .font(.welloEntête)
                                        .foregroundStyle(WelloTheme.ink)
                                }
                                Text(c.explication)
                                    .font(.welloProseDouce)
                                    .foregroundStyle(WelloTheme.ink)
                                Text(c.source)
                                    .font(.welloLégendeMini)
                                    .foregroundStyle(WelloTheme.inkSoft)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }

                    Text("L'hydratation est une plage, pas une cible au millilitre : ces valeurs sont indicatives, non médicales. En cas de doute, demande conseil à un professionnel de santé.")
                        .font(.welloLégendeMini)
                        .foregroundStyle(WelloTheme.inkSoft)
                        .padding(.horizontal, 4)
                        .padding(.top, 4)
                }
                .padding()
            }
            .welloBackground()
            .navigationTitle("Méthode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }
}

#if DEBUG
#Preview("Méthode") { MéthodeView() }
#Preview("Détail") { ComposanteDetailView(composante: .activité) }
#endif
