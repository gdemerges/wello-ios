import SwiftUI
import SwiftData
import Charts
import WelloKit

/// Écran d'analyses détaillées (Wello+) : taux d'atteinte, tendance, meilleure série,
/// répartition horaire. Pattern MV : lit @Query et délègue tout calcul à HydrationStats.
struct AnalyticsView: View {
    @Query(sort: \DailyGoal.date, order: .reverse) private var objectifs: [DailyGoal]
    @Query private var logs: [HydrationLog]
    @Environment(EntitlementStore.self) private var entitlements
    @State private var paywall = false

    /// En gratuit, l'écran s'auto-verrouille en aperçu (le gating vit ici, pas chez l'appelant).
    private var aperçu: Bool { !entitlements.isUnlocked(.analytics) }

    var body: some View {
        Group {
            if objectifs.isEmpty {
                étatVide
            } else if aperçu {
                aperçuVerrouillé
            } else {
                contenu
            }
        }
        .welloBackground()
        .navigationTitle("Analyses")
        .sheet(isPresented: $paywall) {
            PaywallView(bénéfice: "Analyses et tendances détaillées")
        }
    }

    /// Teaser Wello+ : les vraies analyses de l'utilisateur, floutées — on montre ce qu'il
    /// rate (ses données, ses formes) plutôt qu'un cadenas abstrait — sous un panneau
    /// flottant qui ouvre le paywall. Contenu inerte (ni tap ni VoiceOver).
    private var aperçuVerrouillé: some View {
        contenu
            .blur(radius: 5)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .overlay {
                VStack(spacing: 12) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(WelloTheme.accentGradient)
                        .accessibilityHidden(true)
                    Text("Tes analyses t'attendent")
                        .font(.welloEntête)
                        .foregroundStyle(WelloTheme.ink)
                    Text("Taux d'atteinte, tendance, répartition")
                        .font(.welloProseDouce)
                        .foregroundStyle(WelloTheme.inkSoft)
                        .multilineTextAlignment(.center)
                    Button {
                        paywall = true
                    } label: {
                        Text("Essayer gratuitement 7 jours")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 12)
                            .background(WelloTheme.accentGradient, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Ouvre l'offre Wello+")
                }
                .padding(24)
                .background(WelloTheme.canvas.opacity(0.85),
                            in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(32)
            }
    }

    private var contenu: some View {
        let totals = totalsParJour()
        return ScrollView {
            LazyVStack(spacing: 16) {
                tauxCard(totals)
                tendanceCard(totals)
                meilleureSérieCard(totals)
                répartitionCard()
                boissonsCard()
                insightsCard()
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

    /// Prises des 30 derniers jours, avec volume brut + hydratation effective.
    private func entréesBoissons() -> [DrinkStatsEntry] {
        let cal = Calendar.current
        let borne = cal.date(byAdding: .day, value: -29, to: cal.startOfDay(for: .now))!
        return logs
            .filter { $0.loggedAt >= borne }
            .map {
                DrinkStatsEntry(drink: $0.drink,
                                volumeML: $0.amountML,
                                effectiveML: $0.effectiveML,
                                hour: cal.component(.hour, from: $0.loggedAt))
            }
    }

    // MARK: Cartes

    private func tauxCard(_ totals: [DailyTotal]) -> some View {
        let taux7 = HydrationStats.reachRate(Array(totals.prefix(7)))
        let taux30 = HydrationStats.reachRate(Array(totals.prefix(30)))
        return VoilePanel {
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
        let teinte: Color = delta > 0 ? WelloTheme.success : (delta < 0 ? .orange : WelloTheme.inkSoft)
        let résumé = delta == 0 ? "stable vs 30 j" : "\(delta > 0 ? "+" : "−")\(litres(abs(delta))) vs 30 j"
        let étatA11y = delta == 0
            ? "stable par rapport à la moyenne 30 jours"
            : "\(delta > 0 ? "en hausse de" : "en baisse de") \(litres(abs(delta))) par rapport à la moyenne 30 jours"
        return VoilePanel {
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
        return VoilePanel {
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
                    videCarte("clock", "Aucune prise enregistrée sur les 30 derniers jours.")
                } else {
                    Chart {
                        ForEach(répartition, id: \.period) { tranche in
                            BarMark(
                                x: .value("Tranche", tranche.period.libellé),
                                y: .value("ml", tranche.ml)
                            )
                            .foregroundStyle(WelloTheme.accent)
                            .cornerRadius(4)
                            .accessibilityLabel(tranche.period.libellé)
                            .accessibilityValue("\(tranche.ml) millilitres")
                        }
                    }
                    .frame(height: 170)
                }
            }
        }
    }

    private func boissonsCard() -> some View {
        let entries = entréesBoissons()
        let familles = DrinkStats.byFamily(entries)
        let détails = DrinkStats.byDrink(entries).prefix(4)
        return CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                titre("Boissons (30 j)")
                if entries.isEmpty {
                    videCarte("cup.and.saucer", "Aucune prise enregistrée sur les 30 derniers jours.")
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(familles) { stat in
                            familleTuile(stat)
                        }
                    }
                    Divider().overlay(WelloTheme.inkSoft.opacity(0.25))
                    VStack(spacing: 8) {
                        ForEach(Array(détails), id: \.id) { stat in
                            boissonLigne(stat)
                        }
                    }
                }
            }
        }
    }

    private func familleTuile(_ stat: DrinkFamilyStat) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(stat.family.libellé)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(WelloTheme.inkSoft)
            Text(litres(stat.effectiveML))
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(couleurFamille(stat.family))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text("\(stat.volumeML) ml bruts")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(WelloTheme.inkSoft)
            if let période = stat.dominantPeriod {
                Text("surtout \(période.libellé.lowercased())")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(WelloTheme.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(couleurFamille(stat.family).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func boissonLigne(_ stat: DrinkStat) -> some View {
        HStack(spacing: 12) {
            Image(systemName: stat.drink.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(couleurFamille(stat.family))
                .frame(width: 30, height: 30)
                .background(couleurFamille(stat.family).opacity(0.15), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(stat.drink.libellé)
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .foregroundStyle(WelloTheme.ink)
                Text(stat.dominantPeriod.map { "créneau dominant : \($0.libellé.lowercased())" } ?? "\(stat.count) prise(s)")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(WelloTheme.inkSoft)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(litres(stat.effectiveML))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(WelloTheme.ink)
                Text("effectifs")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(WelloTheme.inkSoft)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func couleurFamille(_ famille: DrinkFamily) -> Color {
        switch famille {
        case .water: WelloTheme.accent
        case .caffeine: .brown
        case .alcohol: .purple
        case .sweet: .orange
        case .other: WelloTheme.accentDeep
        }
    }

    // MARK: Insights

    /// Enseignements tirés de la répartition horaire (« tu bois surtout le matin », « tes
    /// après-midis décrochent »…). Masquée tant qu'il n'y a pas assez de recul.
    @ViewBuilder
    private func insightsCard() -> some View {
        let insights = GénérateurInsights.analyser(HydrationStats.hydrationByPeriod(entréesHoraires()))
        if !insights.isEmpty {
            CardContainer {
                VStack(alignment: .leading, spacing: 12) {
                    titre("Ce qu'on observe")
                    ForEach(insights) { insight in
                        HStack(spacing: 12) {
                            Image(systemName: iconeInsight(insight))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(WelloTheme.accent)
                                .frame(width: 34, height: 34)
                                .background(WelloTheme.accent.opacity(0.15), in: Circle())
                                .accessibilityHidden(true)
                            Text(texteInsight(insight))
                                .font(.welloProse)
                                .foregroundStyle(WelloTheme.ink)
                            Spacer(minLength: 0)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private func iconeInsight(_ insight: Insight) -> String {
        switch insight.genre {
        case .pic:       "arrow.up.forward.circle.fill"
        case .creux:     "arrow.down.forward.circle.fill"
        case .tardif:    "moon.stars.fill"
        case .équilibré: "checkmark.seal.fill"
        }
    }

    /// Rendu localisé d'un insight sémantique (WelloKit) → phrase FR (fallback pour les autres langues).
    private func texteInsight(_ insight: Insight) -> LocalizedStringKey {
        switch (insight.genre, insight.période) {
        case (.pic, .matin):     "Tu bois surtout le matin — beau réflexe pour démarrer hydraté."
        case (.pic, .midi):      "Ton pic d'hydratation est à la mi-journée."
        case (.pic, .apresMidi): "Tu bois surtout l'après-midi."
        case (.pic, .soiree):    "Tu bois surtout en soirée."
        case (.pic, _):          "Tu as une tranche horaire nettement plus arrosée."
        case (.creux, .matin):   "Tes matinées sont en retrait — un verre au réveil aide à rattraper."
        case (.creux, .midi):    "Le midi décroche — pense à boire au déjeuner."
        case (.creux, .apresMidi): "Tes après-midis décrochent — cale un verre vers 16 h."
        case (.creux, .soiree):  "Tu bois peu en soirée."
        case (.creux, _):        "Une tranche de la journée reste en retrait."
        case (.tardif, _):       "Une bonne part de ton eau part le soir ou la nuit — avancer un peu réduit les réveils nocturnes."
        case (.équilibré, _):    "Ton hydratation est bien répartie sur la journée. 👌"
        }
    }

    // MARK: Helpers présentation

    private func titre(_ texte: String) -> some View {
        Text(texte)
            .font(.welloEntête)
            .foregroundStyle(WelloTheme.ink)
    }

    // Sous-état vide d'une carte (répartition, boissons) : icône + texte centrés, à la place
    // du graphe/grille absent — cohérent avec les écrans vides plutôt qu'un texte nu à gauche.
    private func videCarte(_ icon: String, _ texte: LocalizedStringKey) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundStyle(WelloTheme.accent.opacity(0.5))
            Text(texte)
                .font(.welloProseDouce)
                .foregroundStyle(WelloTheme.inkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // Pastille de valeur (posée sur le voile de sa carte) : fond `card` solide → contraste net
    // sans réintroduire une carte élevée dans un panneau voile.
    private func tuile(_ valeur: String, _ légende: String, _ icon: String, _ teinte: Color) -> some View {
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
        .padding(14)
        .background(WelloTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(légende) : \(valeur)")
    }

    private func pourcent(_ ratio: Double) -> String {
        "\(Int((ratio * 100).rounded()))%"
    }

    private func litres(_ ml: Int) -> String {
        let f = NumberFormatter()
        f.locale = .current
        f.maximumFractionDigits = 1
        return (f.string(from: NSNumber(value: Double(ml) / 1000)) ?? "0") + " L"
    }

    private var étatVide: some View {
        // Comme l'Historique, on esquisse derrière le texte la forme des analyses à venir
        // (tuiles de taux + histogramme fantômes) plutôt qu'un simple aplat : l'écran vide
        // annonce sa future densité au lieu de sembler cassé.
        ZStack {
            analysesFantômes
                .padding(.horizontal, 24)
                .accessibilityHidden(true)
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
            .padding(24)
            .background(WelloTheme.canvas.opacity(0.55), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .padding(40)
    }

    /// Esquisse fantôme des analyses à venir : deux tuiles de taux + un histogramme de
    /// répartition (hauteurs fixes, aucune donnée), à l'aplomb des vraies cartes.
    private var analysesFantômes: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                tuileFantôme
                tuileFantôme
            }
            HStack(alignment: .bottom, spacing: 10) {
                ForEach([0.5, 0.85, 0.65, 0.95, 0.55, 0.7, 0.45], id: \.self) { h in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(WelloTheme.accent.opacity(0.10))
                        .frame(maxWidth: .infinity)
                        .frame(height: 120 * h)
                }
            }
            .frame(height: 120)
        }
    }

    private var tuileFantôme: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(WelloTheme.accent.opacity(0.08))
            .frame(height: 84)
            .frame(maxWidth: .infinity)
    }
}

#if DEBUG
#Preview("Wello+") {
    NavigationStack {
        AnalyticsView()
            .modelContainer(PreviewSupport.container())
            .environment(PreviewSupport.entitlements(.plus))
    }
}

#Preview("Aperçu (gratuit)") {
    NavigationStack {
        AnalyticsView()
            .modelContainer(PreviewSupport.container())
            .environment(PreviewSupport.entitlements(.free))
    }
}
#endif
