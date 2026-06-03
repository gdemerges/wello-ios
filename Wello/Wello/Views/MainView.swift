import SwiftUI
import SwiftData
import WelloKit

/// Écran principal : jauge « verre d'eau », boutons de log rapide et détail de l'objectif.
struct MainView: View {
    @Environment(HydrationStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    /// Tous les logs (tri récent→ancien) ; on filtre « aujourd'hui » à l'affichage pour rester
    /// correct au passage de minuit sans prédicat figé à l'init.
    @Query(sort: \HydrationLog.loggedAt, order: .reverse) private var tousLogs: [HydrationLog]
    @Query private var profils: [UserProfile]
    /// Reflète l'état « rappels coupés pour aujourd'hui » (retour visuel de la cloche).
    @State private var rappelsCoupésAujourdhui = false
    @State private var afficheSaisie = false
    @State private var fête = false

    private var logsDuJour: [HydrationLog] {
        tousLogs.filter { Calendar.current.isDateInToday($0.loggedAt) }
    }
    private var consommé: Int { logsDuJour.reduce(0) { $0 + $1.amountML } }
    private var objectif: Int { store.breakdown?.totalML ?? 0 }
    private var objectifAtteint: Bool { objectif > 0 && consommé >= objectif }
    private var montants: [Int] { profils.first?.quickAdds ?? [150, 250, 500] }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    WaterGaugeView(consomméML: consommé, objectifML: objectif)
                        .padding(.top, 8)

                    HStack(spacing: 14) {
                        ForEach(Array(montants.enumerated()), id: \.offset) { _, ml in
                            WaterLogButton(ml: ml) { await store.log(ml: ml) }
                        }
                    }
                    .padding(.horizontal)

                    Button { afficheSaisie = true } label: {
                        Label("Autre quantité", systemImage: "slider.horizontal.3")
                            .font(.system(.subheadline, design: .rounded).weight(.medium))
                            .foregroundStyle(WelloTheme.accentDeep)
                    }
                    .buttonStyle(.plain)

                    if let dernière = logsDuJour.first {
                        Button {
                            Task { await store.annulerDernièrePrise() }
                        } label: {
                            Label("Annuler la dernière prise (+\(dernière.amountML) ml)",
                                  systemImage: "arrow.uturn.backward")
                                .font(.system(.subheadline, design: .rounded))
                        }
                        .foregroundStyle(WelloTheme.inkSoft)
                    }

                    if rappelsCoupésAujourdhui {
                        Label("Rappels coupés pour aujourd'hui", systemImage: "bell.slash.fill")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(WelloTheme.inkSoft)
                    }

                    if let breakdown = store.breakdown {
                        BreakdownCard(breakdown: breakdown,
                                      météoIndisponible: store.météoIndisponible)
                            .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .welloBackground()
            .navigationTitle("Wello")
            .navigationBarTitleDisplayMode(.inline)
            .overlay(alignment: .top) { bannièreFête }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    WelloWordmark()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            if rappelsCoupésAujourdhui {
                                await store.refreshToday()          // réactive et replanifie
                            } else {
                                await store.couperRappelsAujourdhui()
                            }
                            rappelsCoupésAujourdhui.toggle()
                        }
                    } label: {
                        Label(rappelsCoupésAujourdhui ? "Réactiver les rappels" : "Couper les rappels aujourd'hui",
                              systemImage: rappelsCoupésAujourdhui ? "bell.slash.fill" : "bell")
                    }
                }
            }
            .task { await store.refreshToday() }
            // Bascule de jour / retour au premier plan : on recalcule l'objectif et le consommé.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await store.refreshToday() } }
            }
            .onChange(of: objectifAtteint) { _, atteint in
                if atteint { déclencherFête() }
            }
            .sheet(isPresented: $afficheSaisie) {
                SaisieEauSheet { ml in Task { await store.log(ml: ml) } }
            }
            // Retour haptique : vibration légère à chaque ajout, succès à l'atteinte de l'objectif.
            .sensoryFeedback(trigger: consommé) { ancien, nouveau in
                nouveau > ancien ? .impact(weight: .light) : nil
            }
            .sensoryFeedback(trigger: objectifAtteint) { _, atteint in
                atteint ? .success : nil
            }
        }
    }

    @ViewBuilder private var bannièreFête: some View {
        if fête {
            Label("Objectif atteint ! 🎉", systemImage: "checkmark.seal.fill")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(WelloTheme.accentGradient, in: Capsule())
                .shadow(color: WelloTheme.accent.opacity(0.4), radius: 10, y: 4)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func déclencherFête() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { fête = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation(.easeOut(duration: 0.5)) { fête = false }
        }
    }
}

/// Feuille de saisie d'une quantité d'eau ponctuelle (bouton « Autre »).
private struct SaisieEauSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var ml = 300
    let onConfirm: (Int) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Stepper(value: $ml, in: 10...3000, step: 10) {
                    HStack {
                        Text("Quantité").font(.system(.body, design: .rounded))
                        Spacer()
                        Text("\(ml) ml")
                            .font(.system(.body, design: .rounded).weight(.medium))
                            .foregroundStyle(WelloTheme.inkSoft)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .welloBackground()
            .navigationTitle("Ajouter de l'eau")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") { onConfirm(ml); dismiss() }
                }
            }
        }
        .presentationDetents([.height(200)])
    }
}

#if DEBUG
#Preview {
    let container = PreviewSupport.container()
    return MainView()
        .modelContainer(container)
        .environment(PreviewSupport.store(container))
}
#endif
