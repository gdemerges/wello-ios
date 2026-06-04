import SwiftUI
import SwiftData
import Charts
import WelloKit

/// Historique : graphe consommé vs objectif, statistiques, et jours détaillables.
struct HistoryView: View {
    @Query(sort: \DailyGoal.date, order: .reverse) private var objectifs: [DailyGoal]
    @Query private var logs: [HydrationLog]
    @State private var plage = 7
    @Environment(EntitlementStore.self) private var entitlements
    @State private var paywall = false

    var body: some View {
        NavigationStack {
            Group {
                if objectifs.isEmpty {
                    étatVide
                } else {
                    contenu
                }
            }
            .welloBackground()
            .navigationTitle("Historique")
            .sheet(isPresented: $paywall) {
                PaywallView(bénéfice: "Garde tout ton historique")
            }
        }
    }

    /// Borne basse de l'historique selon le palier (nil = illimité).
    private var horizon: Date? {
        historyVisibleSince(status: entitlements.status, now: .now)
    }

    /// Objectifs réellement affichables au palier courant.
    private var objectifsVisibles: [DailyGoal] {
        guard let horizon else { return objectifs }
        return objectifs.filter { $0.date >= horizon }
    }

    /// Un seul passage sur les logs par rendu : on construit le consommé par jour une fois,
    /// puis on le consulte partout (graphe, stats, cartes) → O(logs + jours) au lieu de O(jours × logs).
    private var contenu: some View {
        let conso = consommationParJour()
        let premium = entitlements.isUnlocked(.unlimitedHistory)
        return ScrollView {
            LazyVStack(spacing: 16) {
                if premium { sélecteurPlage }
                grapheCard(conso)
                statsCard(conso)
                ForEach(objectifsVisibles) { goal in
                    NavigationLink {
                        DayDetailView(date: goal.date)
                    } label: {
                        carteJour(goal, conso: conso)
                    }
                    .buttonStyle(.plain)
                }
                if !premium && objectifs.count > objectifsVisibles.count {
                    PremiumGateCard(bénéfice: "Historique complet et illimité") {
                        paywall = true
                    }
                }
            }
            .padding()
        }
    }

    /// Consommé (ml) par jour, agrégé en un seul passage sur les logs.
    private func consommationParJour() -> [Date: Int] {
        let cal = Calendar.current
        var map: [Date: Int] = [:]
        for log in logs {
            map[cal.startOfDay(for: log.loggedAt), default: 0] += log.amountML
        }
        return map
    }

    private func consommé(_ conso: [Date: Int], pour jour: Date) -> Int {
        conso[Calendar.current.startOfDay(for: jour)] ?? 0
    }

    // MARK: Sélecteur 7 / 30 jours

    private var sélecteurPlage: some View {
        Picker("Plage", selection: $plage) {
            Text("7 jours").tag(7)
            Text("30 jours").tag(30)
        }
        .pickerStyle(.segmented)
    }

    // MARK: Graphe

    private struct JourBarre: Identifiable {
        let id: Date
        let date: Date
        let consommé: Int
        let objectif: Int
        var atteint: Bool { objectif > 0 && consommé >= objectif }
        var ratio: Double { objectif > 0 ? Double(consommé) / Double(objectif) : 0 }
    }

    private func barres(_ conso: [Date: Int]) -> [JourBarre] {
        objectifsVisibles.prefix(plage).map {
            JourBarre(id: $0.date, date: $0.date, consommé: consommé(conso, pour: $0.date), objectif: $0.totalML)
        }
        .reversed()   // chronologique pour l'axe X
    }

    private func grapheCard(_ conso: [Date: Int]) -> some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                Text("Atteinte de l'objectif")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(WelloTheme.ink)
                Chart {
                    ForEach(barres(conso)) { jour in
                        BarMark(
                            x: .value("Jour", jour.date, unit: .day),
                            y: .value("Atteinte", min(jour.ratio, 1.2))
                        )
                        .foregroundStyle(jour.atteint ? Color.green : WelloTheme.accent)
                        .cornerRadius(4)
                        .accessibilityLabel(jour.date.formatted(.dateTime.weekday(.wide).day().month()))
                        .accessibilityValue("\(jour.consommé) sur \(jour.objectif) millilitres, \(Int((jour.ratio * 100).rounded())) pour cent, \(jour.atteint ? "objectif atteint" : "objectif non atteint")")
                    }
                    RuleMark(y: .value("Objectif", 1.0))
                        .foregroundStyle(WelloTheme.inkSoft.opacity(0.55))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .annotation(position: .topTrailing, alignment: .trailing) {
                            Text("objectif")
                                .font(.system(.caption2, design: .rounded))
                                .foregroundStyle(WelloTheme.inkSoft)
                        }
                }
                .chartYScale(domain: 0...1.25)
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: plage == 7 ? 1 : 6)) {
                        AxisValueLabel(format: .dateTime.day().month(.narrow))
                    }
                }
                .frame(height: 170)
            }
        }
    }

    // MARK: Stats

    private func totals(_ conso: [Date: Int]) -> [DailyTotal] {
        objectifsVisibles.map { DailyTotal(consumedML: consommé(conso, pour: $0.date), goalML: $0.totalML) }
    }

    private func série(_ conso: [Date: Int]) -> Int {
        // Bornée à la fenêtre visible : pour un utilisateur gratuit la série est donc plafonnée
        // aux 7 derniers jours (comportement voulu, upsell naturel vers Wello+).
        var liste = objectifsVisibles.map { (date: $0.date,
                                     total: DailyTotal(consumedML: consommé(conso, pour: $0.date), goalML: $0.totalML)) }
        // Un « aujourd'hui » encore en cours ne casse pas la série.
        if let premier = liste.first, !premier.total.reached, Calendar.current.isDateInToday(premier.date) {
            liste.removeFirst()
        }
        return HydrationStats.currentStreak(liste.map(\.total))
    }

    private func statsCard(_ conso: [Date: Int]) -> some View {
        HStack(spacing: 12) {
            statTuile("\(série(conso)) j", "série en cours", "flame.fill", .orange)
            statTuile(litres(HydrationStats.averageConsumed(totals(conso), lastN: 7)), "moyenne 7 j", "drop.fill", WelloTheme.accent)
        }
    }

    private func statTuile(_ valeur: String, _ légende: String, _ icon: String, _ teinte: Color) -> some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: icon).foregroundStyle(teinte)
                Text(valeur)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(WelloTheme.ink)
                Text(légende)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(WelloTheme.inkSoft)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Carte jour

    private func carteJour(_ goal: DailyGoal, conso: [Date: Int]) -> some View {
        let bu = consommé(conso, pour: goal.date)
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
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WelloTheme.inkSoft.opacity(0.6))
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

    private func litres(_ ml: Int) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.maximumFractionDigits = 1
        return (f.string(from: NSNumber(value: Double(ml) / 1000)) ?? "0") + " L"
    }
}

#if DEBUG
#Preview("Gratuit") {
    HistoryView()
        .modelContainer(PreviewSupport.container())
        .environment(PreviewSupport.entitlements(.free))
}

#Preview("Wello+") {
    HistoryView()
        .modelContainer(PreviewSupport.container())
        .environment(PreviewSupport.entitlements(.plus))
}
#endif
