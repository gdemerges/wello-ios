import SwiftUI
import WelloKit

/// Onboarding de premier lancement : écrans d'intro + choix obligatoire du sexe (base EFSA),
/// puis une page « valeur révélée » qui montre l'objectif calculé avant d'entrer dans l'app.
struct OnboardingView: View {
    /// Appelé au tap final « Commencer », avec le sexe choisi.
    let onTerminé: (BiologicalSex) -> Void
    @State private var page = 0
    @State private var sexeChoisi: BiologicalSex?
    @State private var méthode = false
    /// Taille de l'illustration suivant Dynamic Type.
    @ScaledMetric(relativeTo: .largeTitle) private var tailleIcône: CGFloat = 72

    // titre/texte en LocalizedStringKey : rendus via Text(p.titre), ils doivent être résolus
    // par le catalogue (un Text(String) les afficherait *verbatim*, donc en français partout).
    private struct Page { let icon: String; let titre: LocalizedStringKey; let texte: LocalizedStringKey }
    private let pages = [
        Page(icon: "drop.fill",
             titre: "Bienvenue dans Wello",
             texte: "Ton suivi d'hydratation personnel, calculé pour toi et 100 % local sur ton iPhone."),
        Page(icon: "figure.run",
             titre: "Un objectif qui s'adapte",
             texte: "Wello ajuste ton objectif du jour selon ton sexe, ton activité (Santé), la météo et ta situation (grossesse, allaitement, besoin rénal)."),
        Page(icon: "checkmark.shield.fill",
             titre: "Tes autorisations",
             texte: "Santé, localisation et notifications affinent le calcul et les rappels. Tout refus est géré : l'app reste pleinement utilisable en saisie manuelle."),
    ]

    /// Index de la page de choix du sexe (après les pages d'intro).
    private var pageSexe: Int { pages.count }
    /// Index de la page « valeur révélée » (après le choix du sexe).
    private var pageRévélation: Int { pages.count + 1 }
    private var estDernièrePage: Bool { page == pageRévélation }
    /// Sur la page de sexe, on bloque tant qu'aucun choix n'est fait.
    private var boutonBloqué: Bool { page == pageSexe && sexeChoisi == nil }

    /// Objectif de base (EFSA) révélé en fin d'onboarding : calcul pur, sans activité ni météo
    /// (elles viennent au 1ᵉʳ refresh). C'est le socle scientifique personnalisé au sexe.
    private var objectifRévélé: GoalBreakdown? {
        guard let sexe = sexeChoisi else { return nil }
        return HydrationCalculator().calculate(
            CalculatorInputs(sex: sexe, activeEnergyKcal: 0, weather: nil,
                             physiologicalState: .aucun, renalBonusML: 0,
                             bodyWeightKg: nil, tuning: .neutre))
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { i in
                    pageVue(pages[i]).tag(i)
                }
                sexeVue.tag(pageSexe)
                révélationVue.tag(pageRévélation)
            }
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .animation(.easeInOut, value: page)

            Button {
                if !estDernièrePage {
                    if boutonBloqué { return }
                    withAnimation { page += 1 }
                } else if let sexeChoisi {
                    onTerminé(sexeChoisi)
                }
            } label: {
                Text(libelléBouton)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(WelloTheme.accentGradient,
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .opacity(boutonBloqué ? 0.5 : 1)
            }
            .buttonStyle(.plain)
            .disabled(boutonBloqué)
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
        .welloBackground()
        .sheet(isPresented: $méthode) { MéthodeView() }
    }

    private var libelléBouton: LocalizedStringKey {
        if page == pageSexe { return "Voir mon objectif" }
        if estDernièrePage { return "Commencer" }
        return "Suivant"
    }

    private func pageVue(_ p: Page) -> some View {
        VStack(spacing: 22) {
            Image(systemName: p.icon)
                .font(.system(size: tailleIcône, weight: .semibold))
                .foregroundStyle(WelloTheme.accentGradient)
                .accessibilityHidden(true)   // décorative : le titre/texte porte le sens
            Text(p.titre)
                .font(.welloTitreÉcran)
                .foregroundStyle(WelloTheme.ink)
                .multilineTextAlignment(.center)
            Text(p.texte)
                .font(.welloProse)
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
                .font(.welloTitreÉcran)
                .foregroundStyle(WelloTheme.ink)
            Text("Il fixe ta base d'hydratation selon les apports de référence EFSA.")
                .font(.welloProse)
                .foregroundStyle(WelloTheme.inkSoft)
                .multilineTextAlignment(.center)
            HStack(spacing: 14) {
                choixSexe(.homme, "Homme")
                choixSexe(.femme, "Femme")
            }
        }
        .padding(.horizontal, 32)
    }

    /// Page « valeur révélée » : le grand chiffre de l'objectif de base + ce qui l'affinera.
    private var révélationVue: some View {
        VStack(spacing: 20) {
            Image(systemName: "drop.fill")
                .font(.system(size: tailleIcône * 0.7, weight: .semibold))
                .foregroundStyle(WelloTheme.accentGradient)
                .accessibilityHidden(true)

            VStack(spacing: 4) {
                Text("Ton objectif personnalisé")
                    .font(.welloTitre)
                    .foregroundStyle(WelloTheme.ink)
                    .multilineTextAlignment(.center)
                Text("\(objectifRévélé?.totalML ?? 0) ml")
                    .font(.system(size: 52, weight: .heavy, design: .rounded))
                    .foregroundStyle(WelloTheme.accentGradient)
                    .contentTransition(.numericText())
                    .accessibilityLabel("\(objectifRévélé?.totalML ?? 0) millilitres par jour")
                Text("par jour")
                    .font(.welloLégende)
                    .foregroundStyle(WelloTheme.inkSoft)
            }

            CardContainer {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Base scientifique (EFSA)", systemImage: "book.closed.fill")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(WelloTheme.inkSoft)
                        Spacer()
                        Text("\(objectifRévélé?.baseML ?? 0) ml")
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .foregroundStyle(WelloTheme.ink)
                    }
                    .accessibilityElement(children: .combine)

                    Divider().overlay(WelloTheme.inkSoft.opacity(0.25))

                    Text("Chaque jour, Wello ajuste ce socle automatiquement :")
                        .font(.welloLégende)
                        .foregroundStyle(WelloTheme.inkSoft)
                    HStack(spacing: 8) {
                        facteur("figure.run", "Activité")
                        facteur("thermometer.sun.fill", "Météo")
                        facteur("mountain.2.fill", "Altitude")
                    }
                }
            }

            Button { méthode = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                    Text("Comment est-il calculé ?")
                }
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .foregroundStyle(WelloTheme.accentDeep)
                .frame(minHeight: 44)
            }
        }
        .padding(.horizontal, 28)
    }

    /// Petite pastille « facteur d'ajustement » (activité / météo / altitude).
    private func facteur(_ icon: String, _ titre: LocalizedStringKey) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WelloTheme.accent)
            Text(titre)
                .font(.welloLégendeMini)
                .foregroundStyle(WelloTheme.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(WelloTheme.accent.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func choixSexe(_ valeur: BiologicalSex, _ titre: LocalizedStringKey) -> some View {
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
