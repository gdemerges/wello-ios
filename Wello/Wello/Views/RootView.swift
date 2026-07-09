import SwiftUI
import SwiftData
import WelloKit

/// Racine de l'app : les 3 onglets, avec l'onboarding en plein écran tant que le 1er lancement
/// n'est pas terminé OU que le sexe (base EFSA) n'est pas renseigné.
struct RootView: View {
    @Environment(HydrationStore.self) private var store
    @Environment(ThemeStore.self) private var theme
    @Query private var profils: [UserProfile]
    @AppStorage("wello.hasOnboarded") private var hasOnboarded = false
    /// Onglet courant, conservé dans RootView : survit au rebuild déclenché par `.id` au changement de thème.
    @State private var onglet = 0

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
            }
        }
    }
}
