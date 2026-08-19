import SwiftUI
import SwiftData
import WelloKit

/// Racine de l'app : les 3 onglets, avec l'onboarding en plein écran tant que le 1er lancement
/// n'est pas terminé OU que le sexe (base EFSA) n'est pas renseigné.
struct RootView: View {
    @Environment(HydrationStore.self) private var store
    @Environment(ThemeStore.self) private var theme
    @Environment(EntitlementStore.self) private var entitlements
    @Query private var profils: [UserProfile]
    @AppStorage("wello.hasOnboarded") private var hasOnboarded = false
    /// L'offre d'accueil ne se présente **qu'une fois**, au tout premier lancement. Ensuite,
    /// Wello+ ne se rappelle au bon souvenir que par gating contextuel (verrou tapé) ou depuis
    /// le Profil : pas de relance, pas d'insistance.
    @AppStorage("wello.paywallAccueilVu") private var paywallAccueilVu = false
    /// Onglet courant, conservé dans RootView : survit au rebuild déclenché par `.id` au changement de thème.
    @State private var onglet = 0
    @State private var paywallAccueil = false

    /// Vrai si aucun profil ou profil sans sexe renseigné.
    private var sexeManquant: Bool { (profils.first?.sexe) == nil }

    var body: some View {
        TabView(selection: $onglet) {
            MainView(estActif: onglet == 0)
                .tabItem { Label("Aujourd'hui", systemImage: "drop.fill") }
                .tag(0)
            HistoryView()
                .tabItem { Label("Historique", systemImage: "calendar") }
                .tag(1)
            ProfileView()
                .tabItem { Label("Profil", systemImage: "person.fill") }
                .tag(2)
        }
        .id(theme.selected)   // rebuild de l'arbre quand le thème change → réévalue les teintes WelloTheme
        .tint(WelloTheme.accent)
        .fullScreenCover(isPresented: Binding(get: { !hasOnboarded || sexeManquant },
                                              set: { _ in })) {
            OnboardingView { sexe in
                store.profilCourant().sexe = sexe
                hasOnboarded = true
                Task { await store.refreshToday(force: true) }   // déclenche les demandes d'autorisation
                présenterOffreAccueil()
            }
        }
        .sheet(isPresented: $paywallAccueil) {
            PaywallView(bénéfice: "Essaie Wello+ gratuitement pendant 7 jours", contexteAccueil: true)
        }
    }

    /// Présente l'offre Wello+ juste après l'onboarding — le moment de plus forte intention :
    /// l'utilisateur vient de voir *son* objectif calculé. Sautée si Wello+ est déjà actif
    /// (réinstallation, achat restauré) ou si elle a déjà été montrée.
    private func présenterOffreAccueil() {
        guard !paywallAccueilVu, !entitlements.isUnlocked(.unlimitedHistory) else { return }
        paywallAccueilVu = true
        Task { @MainActor in
            // Laisse le plein écran d'onboarding finir sa disparition : présenter une feuille
            // pendant qu'un `fullScreenCover` se ferme la fait sauter silencieusement.
            try? await Task.sleep(for: .seconds(0.6))
            paywallAccueil = true
        }
    }
}
