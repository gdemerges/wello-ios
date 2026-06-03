import SwiftUI
import SwiftData
import WelloKit

/// Écran principal : jauge de progression, boutons de log rapide et détail de l'objectif.
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
                VStack(spacing: 24) {
                    GaugeView(consomméML: consommé, objectifML: objectif)

                    HStack(spacing: 12) {
                        boutonLog(150)
                        boutonLog(250)
                        boutonLog(500)
                    }
                    .padding(.horizontal)

                    if rappelsCoupésAujourdhui {
                        Label("Rappels coupés pour aujourd'hui", systemImage: "bell.slash.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let breakdown = store.breakdown {
                        BreakdownCard(breakdown: breakdown,
                                      météoIndisponible: store.météoIndisponible)
                            .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Wello")
            .toolbar {
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

    private func boutonLog(_ ml: Int) -> some View {
        Button {
            Task { await store.log(ml: ml) }
        } label: {
            Text("+\(ml)")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
    }
}
