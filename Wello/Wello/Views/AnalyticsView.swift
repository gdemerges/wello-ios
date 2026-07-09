import SwiftUI
import SwiftData
import Charts
import WelloKit

/// Écran d'analyses détaillées (Wello+) : taux d'atteinte, tendance, meilleure série,
/// répartition horaire. Pattern MV : lit @Query et délègue tout calcul à HydrationStats.
struct AnalyticsView: View {
    @Query(sort: \DailyGoal.date, order: .reverse) private var objectifs: [DailyGoal]
    @Query private var logs: [HydrationLog]

    var body: some View {
        Group {
            if objectifs.isEmpty {
                étatVide
            } else {
                contenu
            }
        }
        .welloBackground()
        .navigationTitle("Analyses")
    }

    private var contenu: some View {
        let totals = totalsParJour()
        return ScrollView {
            LazyVStack(spacing: 16) {
                tauxCard(totals)
                tendanceCard(totals)
                meilleureSérieCard(totals)
                répartitionCard()
            }
            .padding()
        }
    }

    // MARK: Données

    /// Consommé effectif (ml) par jour, agrégé en un seul passage sur les logs (jours bornés à ≥ 0).
    private func consommationParJour() -> [Date: Int] {
        let cal = Calendar.current
        var map: [Date: Int] = [:]
        for log in logs {
            map[cal.startOfDay(for: log.loggedAt), default: 0] += log.effectiveML
        }
        return map.mapValues(clampedDayTotal)
    }

    /// Totaux jour (consommé vs objectif), du plus récent au plus ancien.
    private func totalsParJour() -> [DailyTotal] {
        let conso = consommationParJour()
        let cal = Calendar.current
        return objectifs.map { goal in
            DailyTotal(consumedML: conso[cal.startOfDay(for: goal.date)] ?? 0, goalML: goal.totalML)
        }
    }

    /// (heure, hydratation effective) des prises sur les 30 derniers jours, pour la répartition.
    private func entréesHoraires() -> [(hour: Int, ml: Int)] {
        let cal = Calendar.current
        let borne = cal.date(byAdding: .day, value: -29, to: cal.startOfDay(for: .now))!
        return logs
            .filter { $0.loggedAt >= borne }
            .map { (hour: cal.component(.hour, from: $0.loggedAt), ml: max(0, $0.effectiveML)) }
    }

    // MARK: Cartes

    private func tauxCard(_ totals: [DailyTotal]) -> some View {
        let taux7 = HydrationStats.reachRate(Array(totals.prefix(7)))
        let taux30 = HydrationStats.reachRate(Array(totals.prefix(30)))
        return CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                titre("Taux d'atteinte")
                HStack(spacing: 12) {
                    tuile(pourcent(taux7), "sur 7 jours", "target", WelloTheme.accent)
                    tuile(pourcent(taux30), "sur 30 jours", "target", WelloTheme.accentDeep)
                }
            }
        }
    }

    private func tendanceCard(_ totals: [DailyTotal]) -> some View {
        let moy7 = HydrationStats.averageConsumed(totals, lastN: 7)
        let moy30 = HydrationStats.averageConsumed(totals, lastN: 30)
        let delta = moy7 - moy30
        // Trois états : hausse / baisse / stable (delta nul). Stable évite une flèche verte
        // « +0,0 L » trompeuse en début d'usage, quand les deux moyennes coïncident.
        let icon = delta > 0 ? "arrow.up.right" : (delta < 0 ? "arrow.down.right" : "arrow.right")
        let teinte: Color = delta > 0 ? .green : (delta < 0 ? .orange : WelloTheme.inkSoft)
        let résumé = delta == 0 ? "stable vs 30 j" : "\(delta > 0 ? "+" : "−")\(litres(abs(delta))) vs 30 j"
        let étatA11y = delta == 0
            ? "stable par rapport à la moyenne 30 jours"
            : "\(delta > 0 ? "en hausse de" : "en baisse de") \(litres(abs(delta))) par rapport à la moyenne 30 jours"
        return CardContainer {
            VStack(alignment: .leading, spacing: 8) {
                titre("Tendance")
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(litres(moy7))
                        .font(.system(.title, design: .rounded).weight(.bold))
                        .foregroundStyle(WelloTheme.ink)
                    Image(systemName: icon)
                        .foregroundStyle(teinte)
                    Text(résumé)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(WelloTheme.inkSoft)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tendance : moyenne 7 jours \(litres(moy7)), \(étatA11y)")
    }

    private func meilleureSérieCard(_ totals: [DailyTotal]) -> some View {
        let record = HydrationStats.bestStreak(totals)
        return CardContainer {
            HStack(spacing: 14) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(record) jours")
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .foregroundStyle(WelloTheme.ink)
                    Text("meilleure série (record)")
                        .font(.welloLégendeMini)
                        .foregroundStyle(WelloTheme.inkSoft)
                }
                Spacer()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Meilleure série : record de \(record) jours")
    }

    private func répartitionCard() -> some View {
        let répartition = HydrationStats.hydrationByPeriod(entréesHoraires())
        let total = répartition.reduce(0) { $0 + $1.ml }
        return CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                titre("Répartition horaire (30 j)")
                if total == 0 {
                    Text("Aucune prise enregistrée sur les 30 derniers jours.")
                        .font(.welloProseDouce)
                        .foregroundStyle(WelloTheme.inkSoft)
                } else {
                    Chart {
                        ForEach(répartition, id: \.period) { tranche in
                            BarMark(
                                x: .value("Tranche", tranche.period.label),
                                y: .value("ml", tranche.ml)
                            )
                            .foregroundStyle(WelloTheme.accent)
                            .cornerRadius(4)
                            .accessibilityLabel(tranche.period.label)
                            .accessibilityValue("\(tranche.ml) millilitres")
                        }
                    }
                    .frame(height: 170)
                }
            }
        }
    }

    // MARK: Helpers présentation

    private func titre(_ texte: String) -> some View {
        Text(texte)
            .font(.welloEntête)
            .foregroundStyle(WelloTheme.ink)
    }

    private func tuile(_ valeur: String, _ légende: String, _ icon: String, _ teinte: Color) -> some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: icon).foregroundStyle(teinte)
                Text(valeur)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(WelloTheme.ink)
                Text(légende)
                    .font(.welloLégendeMini)
                    .foregroundStyle(WelloTheme.inkSoft)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(légende) : \(valeur)")
    }

    private func pourcent(_ ratio: Double) -> String {
        "\(Int((ratio * 100).rounded()))%"
    }

    private func litres(_ ml: Int) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.maximumFractionDigits = 1
        return (f.string(from: NSNumber(value: Double(ml) / 1000)) ?? "0") + " L"
    }

    private var étatVide: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 44))
                .foregroundStyle(WelloTheme.accent.opacity(0.6))
            Text("Pas encore d'analyses")
                .font(.welloEntête)
                .foregroundStyle(WelloTheme.ink)
            Text("Tes tendances apparaîtront ici au fil des jours de suivi.")
                .font(.welloProseDouce)
                .foregroundStyle(WelloTheme.inkSoft)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        AnalyticsView()
            .modelContainer(PreviewSupport.container())
    }
}
#endif
