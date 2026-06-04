import SwiftUI
import WelloKit

/// Onboarding de premier lancement : écrans d'intro + choix obligatoire du sexe (base EFSA).
struct OnboardingView: View {
    /// Appelé au tap final « Commencer », avec le sexe choisi.
    let onTerminé: (BiologicalSex) -> Void
    @State private var page = 0
    @State private var sexeChoisi: BiologicalSex?
    /// Taille de l'illustration suivant Dynamic Type.
    @ScaledMetric(relativeTo: .largeTitle) private var tailleIcône: CGFloat = 72

    private struct Page { let icon: String; let titre: String; let texte: String }
    private let pages = [
        Page(icon: "drop.fill",
             titre: "Bienvenue dans Wello",
             texte: "Ton suivi d'hydratation personnel, calculé pour toi et 100 % local sur ton iPhone."),
        Page(icon: "figure.run",
             titre: "Un objectif qui s'adapte",
             texte: "Wello ajuste ton objectif du jour selon ton sexe, ton activité (Santé) et la météo — sans jamais descendre sous ton plancher médical."),
        Page(icon: "checkmark.shield.fill",
             titre: "Tes autorisations",
             texte: "Santé, localisation et notifications affinent le calcul et les rappels. Tout refus est géré : l'app reste pleinement utilisable en saisie manuelle."),
    ]

    /// Index de la page de choix du sexe (après les pages d'intro).
    private var pageSexe: Int { pages.count }
    private var estDernièrePage: Bool { page == pageSexe }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { i in
                    pageVue(pages[i]).tag(i)
                }
                sexeVue.tag(pageSexe)
            }
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if !estDernièrePage {
                    withAnimation { page += 1 }
                } else if let sexeChoisi {
                    onTerminé(sexeChoisi)
                }
            } label: {
                Text(estDernièrePage ? "Commencer" : "Suivant")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(WelloTheme.accentGradient,
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .opacity(estDernièrePage && sexeChoisi == nil ? 0.5 : 1)
            }
            .buttonStyle(.plain)
            .disabled(estDernièrePage && sexeChoisi == nil)
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
        .welloBackground()
    }

    private func pageVue(_ p: Page) -> some View {
        VStack(spacing: 22) {
            Image(systemName: p.icon)
                .font(.system(size: tailleIcône, weight: .semibold))
                .foregroundStyle(WelloTheme.accentGradient)
                .accessibilityHidden(true)   // décorative : le titre/texte porte le sens
            Text(p.titre)
                .font(.system(.title, design: .rounded).weight(.bold))
                .foregroundStyle(WelloTheme.ink)
                .multilineTextAlignment(.center)
            Text(p.texte)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(WelloTheme.inkSoft)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
    }

    private var sexeVue: some View {
        VStack(spacing: 22) {
            Image(systemName: "person.fill")
                .font(.system(size: tailleIcône, weight: .semibold))
                .foregroundStyle(WelloTheme.accentGradient)
                .accessibilityHidden(true)
            Text("Ton sexe")
                .font(.system(.title, design: .rounded).weight(.bold))
                .foregroundStyle(WelloTheme.ink)
            Text("Il fixe ta base d'hydratation selon les apports de référence EFSA.")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(WelloTheme.inkSoft)
                .multilineTextAlignment(.center)
            HStack(spacing: 14) {
                choixSexe(.homme, "Homme")
                choixSexe(.femme, "Femme")
            }
        }
        .padding(.horizontal, 32)
    }

    private func choixSexe(_ valeur: BiologicalSex, _ titre: String) -> some View {
        let sélectionné = sexeChoisi == valeur
        return Button {
            sexeChoisi = valeur
        } label: {
            Text(titre)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(sélectionné ? .white : WelloTheme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(sélectionné ? AnyShapeStyle(WelloTheme.accentGradient)
                                        : AnyShapeStyle(WelloTheme.card),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(WelloTheme.accent.opacity(sélectionné ? 0 : 0.35), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(titre)
        .accessibilityAddTraits(sélectionné ? [.isSelected] : [])
    }
}

#if DEBUG
#Preview {
    OnboardingView { _ in }
}
#endif
