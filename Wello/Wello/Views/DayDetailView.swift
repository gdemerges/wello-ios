import SwiftUI
import SwiftData
import WelloKit

/// Détail d'un jour : liste des prises d'eau, suppression par balayage.
struct DayDetailView: View {
    let date: Date
    @Environment(HydrationStore.self) private var store
    @Query(sort: \HydrationLog.loggedAt, order: .reverse) private var tousLogs: [HydrationLog]

    private var prises: [HydrationLog] {
        tousLogs.filter { Calendar.current.isDate($0.loggedAt, inSameDayAs: date) }
    }
    private var total: Int { clampedDayTotal(prises.reduce(0) { $0 + $1.effectiveML }) }

    var body: some View {
        List {
            Section {
                if prises.isEmpty {
                    Text("Aucune prise ce jour-là.")
                        .font(.welloProseDouce)
                        .foregroundStyle(WelloTheme.inkSoft)
                } else {
                    ForEach(prises) { prise in
                        ligne(prise)
                    }
                    .onDelete { indices in
                        let cibles = indices.map { prises[$0] }
                        Task { for c in cibles { await store.supprimer(c) } }
                    }
                }
            } footer: {
                if !prises.isEmpty {
                    Text("Total du jour : \(total) ml — balaie une prise pour la supprimer.")
                        .font(.welloLégendeMini)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .welloBackground()
        .navigationTitle(date.formatted(.dateTime.weekday(.wide).day().month()))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func ligne(_ prise: HydrationLog) -> some View {
        // Nom de la boisson dès qu'elle n'est pas de l'eau (même à coefficient 1.0, ex. lait) ;
        // l'effectif n'est montré que quand le coefficient change le compte (≠ 1.0).
        let nommée = prise.drink != .water
        let effectifAffiché = prise.coefficient != 1.0
        return HStack(spacing: 12) {
            Image(systemName: prise.source == "healthkit" ? "heart.fill" : prise.drink.icon)
                .foregroundStyle(prise.source == "healthkit" ? .pink : WelloTheme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(nommée ? "\(prise.amountML) ml de \(prise.drink.label.lowercased())"
                            : "\(prise.amountML) ml")
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .foregroundStyle(WelloTheme.ink)
                Text(sousTitre(prise, effectifAffiché: effectifAffiché))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(WelloTheme.inkSoft)
            }
            Spacer()
            Text(prise.loggedAt, format: .dateTime.hour().minute())
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(WelloTheme.inkSoft)
        }
    }

    /// Sous-titre : provenance pour l'eau/HealthKit, hydratation effective si le coefficient ≠ 1.0.
    private func sousTitre(_ prise: HydrationLog, effectifAffiché: Bool) -> String {
        if prise.source == "healthkit" { return "depuis Santé" }
        if effectifAffiché { return "≈ \(prise.effectiveML) ml hydratants" }
        return "saisie dans Wello"
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        DayDetailView(date: .now)
            .modelContainer(PreviewSupport.container())
            .environment(PreviewSupport.store(PreviewSupport.container()))
    }
}
#endif
