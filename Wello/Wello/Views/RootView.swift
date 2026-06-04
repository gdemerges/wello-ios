import SwiftUI
import SwiftData
import WelloKit

/// Racine de l'app : les 3 onglets, avec l'onboarding en plein écran tant que le 1er lancement
/// n'est pas terminé OU que le sexe (base EFSA) n'est pas renseigné.
struct RootView: View {
    @Environment(HydrationStore.self) private var store
    @Query private var profils: [UserProfile]
    @AppStorage("wello.hasOnboarded") private var hasOnboarded = false

    /// Vrai si aucun profil ou profil sans sexe renseigné.
    private var sexeManquant: Bool { (profils.first?.sexe) == nil }

    var body: some View {
        TabView {
            MainView()
                .tabItem { Label("Aujourd'hui", systemImage: "drop.fill") }
            HistoryView()
                .tabItem { Label("Historique", systemImage: "calendar") }
            ProfileView()
                .tabItem { Label("Profil", systemImage: "person.fill") }
        }
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
