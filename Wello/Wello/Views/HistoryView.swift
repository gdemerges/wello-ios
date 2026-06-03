import SwiftUI
import SwiftData

/// Historique : objectif vs consommé par jour.
struct HistoryView: View {
    @Query(sort: \DailyGoal.date, order: .reverse) private var objectifs: [DailyGoal]
    @Query private var logs: [HydrationLog]

    var body: some View {
        NavigationStack {
            Group {
                if objectifs.isEmpty {
                    étatVide
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(objectifs) { goal in
                                carteJour(goal)
                            }
                        }
                        .padding()
                    }
                }
            }
            .welloBackground()
            .navigationTitle("Historique")
        }
    }

    private func carteJour(_ goal: DailyGoal) -> some View {
        let bu = consommé(pour: goal.date)
        let atteint = bu >= goal.totalML
        let ratio = goal.totalML > 0 ? min(Double(bu) / Double(goal.totalML), 1) : 0

        return CardContainer {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(goal.date, format: .dateTime.weekday(.wide).day().month())
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(WelloTheme.ink)
                    Spacer()
                    if atteint {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                    }
                }

                ProgressView(value: ratio)
                    .tint(atteint ? .green : WelloTheme.accent)

                HStack {
                    Text("Bu : \(bu) ml")
                        .foregroundStyle(atteint ? .green : WelloTheme.inkSoft)
                    Spacer()
                    Text("Objectif : \(goal.totalML) ml")
                        .foregroundStyle(WelloTheme.inkSoft)
                }
                .font(.system(.subheadline, design: .rounded))
            }
        }
    }

    private var étatVide: some View {
        VStack(spacing: 12) {
            Image(systemName: "drop.fill")
                .font(.system(size: 44))
                .foregroundStyle(WelloTheme.accent.opacity(0.6))
            Text("Aucun historique pour l'instant")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(WelloTheme.ink)
            Text("Tes objectifs quotidiens apparaîtront ici au fil des jours.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(WelloTheme.inkSoft)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }

    private func consommé(pour jour: Date) -> Int {
        let cal = Calendar.current
        return logs.filter { cal.isDate($0.loggedAt, inSameDayAs: jour) }
                   .reduce(0) { $0 + $1.amountML }
    }
}

#if DEBUG
#Preview {
    HistoryView()
        .modelContainer(PreviewSupport.container())
}
#endif
