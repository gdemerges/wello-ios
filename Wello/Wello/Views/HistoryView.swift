import SwiftUI
import SwiftData

/// Historique : objectif vs consommé par jour.
struct HistoryView: View {
    @Query(sort: \DailyGoal.date, order: .reverse) private var objectifs: [DailyGoal]
    @Query private var logs: [HydrationLog]

    var body: some View {
        NavigationStack {
            List(objectifs) { goal in
                let consommé = consommé(pour: goal.date)
                VStack(alignment: .leading, spacing: 4) {
                    Text(goal.date, style: .date).font(.headline)
                    HStack {
                        Text("Objectif : \(goal.totalML) ml")
                        Spacer()
                        Text("Bu : \(consommé) ml")
                            .foregroundStyle(consommé >= goal.totalML ? .green : .secondary)
                    }
                    .font(.subheadline)
                }
            }
            .navigationTitle("Historique")
        }
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
