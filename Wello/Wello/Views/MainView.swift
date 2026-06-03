import SwiftUI
import SwiftData
import WelloKit

/// Écran principal : jauge « verre d'eau », boutons de log rapide et détail de l'objectif.
struct MainView: View {
    @Environment(HydrationStore.self) private var store
    /// On observe les logs du jour pour mettre à jour la jauge automatiquement.
    @Query private var logs: [HydrationLog]
    /// Reflète l'état « rappels coupés pour aujourd'hui » (retour visuel de la cloche).
    @State private var rappelsCoupésAujourdhui = false

    init() {
        // SwiftData n'autorise pas `.now` dans un prédicat de propriété : on le capture via l'init.
        let début = Calendar.current.startOfDay(for: .now)
        _logs = Query(filter: #Predicate<HydrationLog> { $0.loggedAt >= début },
                      sort: \HydrationLog.loggedAt, order: .forward)
    }

    private var consommé: Int { logs.reduce(0) { $0 + $1.amountML } }
    private var objectif: Int { store.breakdown?.totalML ?? 0 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    WaterGaugeView(consomméML: consommé, objectifML: objectif)
                        .padding(.top, 8)

                    HStack(spacing: 14) {
                        WaterLogButton(ml: 150) { await store.log(ml: 150) }
                        WaterLogButton(ml: 250) { await store.log(ml: 250) }
                        WaterLogButton(ml: 500) { await store.log(ml: 500) }
                    }
                    .padding(.horizontal)

                    if let dernière = logs.last {
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
        }
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
