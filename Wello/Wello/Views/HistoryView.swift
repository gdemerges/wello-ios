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
    @State private var partage: SharePayload?
    @State private var erreurExport = false

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
            .toolbar {
                if !objectifs.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            exporter()
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Exporter l'historique")
                    }
                }
            }
            .sheet(isPresented: $paywall) {
                PaywallView(bénéfice: "Garde tout ton historique")
            }
            .sheet(item: $partage) { ShareSheet(urls: $0.urls) }
            .alert("Export impossible", isPresented: $erreurExport) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("La création des fichiers a échoué. Réessaie.")
            }
        }
    }

    /// Génère les deux CSV (prises + jours) et ouvre la feuille de partage. Réservé à Wello+.
    private func exporter() {
        guard entitlements.isUnlocked(.export) else { paywall = true; return }
        do {
            let prises = try HydrationExporter.detailFile(logs: logs)
            let jours = try HydrationExporter.summaryFile(logs: logs, goals: objectifs)
            partage = SharePayload(urls: [prises, jours])
        } catch {
            erreurExport = true
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
                bilanHebdoCard(conso)
                if premium { sélecteurPlage }
                grapheCard(conso)
                statsCard(conso)
                analyseEntrée
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

    /// Accès aux analyses détaillées : NavigationLink en premium, carte de teasing en gratuit.
    @ViewBuilder
    private var analyseEntrée: some View {
        if entitlements.isUnlocked(.analytics) {
            NavigationLink {
                AnalyticsView()
            } label: {
                CardContainer {
                    HStack(spacing: 14) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 20))
                            .foregroundStyle(WelloTheme.accent)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Analyses détaillées")
                                .font(.welloEntête)
                                .foregroundStyle(WelloTheme.ink)
                            Text("Taux d'atteinte, tendance, répartition")
                                .font(.welloProseDouce)
                                .foregroundStyle(WelloTheme.inkSoft)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(WelloTheme.inkSoft.opacity(0.6))
                            .accessibilityHidden(true)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Analyses détaillées")
            .accessibilityHint("Ouvre les analyses et tendances")
        } else {
            PremiumGateCard(bénéfice: "Analyses et tendances détaillées") {
                paywall = true
            }
        }
    }

    /// Consommé effectif (ml) par jour, agrégé en un seul passage sur les logs.
    /// Chaque jour est borné à ≥ 0 (une journée « alcool » ne devient pas négative).
    private func consommationParJour() -> [Date: Int] {
        let cal = Calendar.current
        var map: [Date: Int] = [:]
        for log in logs {
            map[cal.startOfDay(for: log.loggedAt), default: 0] += log.effectiveML
        }
        return map.mapValues(clampedDayTotal)
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

    // MARK: Bilan de la semaine

    /// Carte de synthèse hebdomadaire (gratuite) : jours atteints + tendance + action concrète.
    /// La comparaison n'apparaît qu'avec assez d'historique (gratuit borné à 7 j → pas de delta).
    @ViewBuilder
    private func bilanHebdoCard(_ conso: [Date: Int]) -> some View {
        if let bilan = BilanHebdomadaire.calculer(joursRécents: Array(totals(conso).prefix(14))) {
            CardContainer {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(WelloTheme.accentDeep)
                            .frame(width: 36, height: 36)
                            .background(WelloTheme.accentDeep.opacity(0.14), in: Circle())
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(titreBilanHebdo)
                                .font(.welloEntête)
                                .foregroundStyle(WelloTheme.ink)
                            Text("Moyenne \(litres(bilan.moyenneML)) par jour")
                                .font(.welloProseDouce)
                                .foregroundStyle(WelloTheme.inkSoft)
                        }
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(bilan.joursAtteints)/\(bilan.joursComptés)")
                            .font(.system(.title, design: .rounded).weight(.bold))
                            .foregroundStyle(WelloTheme.ink)
                        Text("objectifs atteints")
                            .font(.welloProseDouce)
                            .foregroundStyle(WelloTheme.inkSoft)
                    }
                    if bilan.aComparaison {
                        tendanceLigne(bilan)
                    } else {
                        Text("On construit encore ton recul pour comparer avec la semaine passée.")
                            .font(.welloProseDouce)
                            .foregroundStyle(WelloTheme.inkSoft)
                    }

                    Label(actionRoutine(bilan), systemImage: "sparkles")
                        .font(.system(.subheadline, design: .rounded).weight(.medium))
                        .foregroundStyle(WelloTheme.accentDeep)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// Ligne de tendance vs semaine précédente (flèche + écart en litres, coloré).
    private func tendanceLigne(_ bilan: BilanHebdo) -> some View {
        let (icon, teinte): (String, Color) = switch bilan.tendance {
        case .hausse: ("arrow.up.right", .green)
        case .baisse: ("arrow.down.right", .orange)
        case .stable: ("arrow.right", WelloTheme.inkSoft)
        }
        let signe = bilan.deltaML > 0 ? "+" : (bilan.deltaML < 0 ? "−" : "")
        let texte: LocalizedStringKey = bilan.tendance == .stable
            ? "stable vs semaine passée"
            : "\(signe)\(litres(abs(bilan.deltaML))) vs semaine passée"
        return Label {
            Text(texte).font(.welloProseDouce)
        } icon: {
            Image(systemName: icon)
        }
        .foregroundStyle(teinte)
    }

    private var titreBilanHebdo: LocalizedStringKey {
        let weekday = Calendar.current.component(.weekday, from: .now)
        return (weekday == 1 || weekday == 2) ? "Bilan & cap de la semaine" : "Cette semaine"
    }

    private func actionRoutine(_ bilan: BilanHebdo) -> LocalizedStringKey {
        if bilan.joursComptés >= 5 && bilan.joursAtteints <= 2 {
            return "Action : ajoute un verre fixe au réveil et un autre au goûter."
        }
        if bilan.aComparaison && bilan.tendance == .baisse {
            return "Action : garde les rappels actifs cette semaine, surtout l'après-midi."
        }
        if bilan.joursAtteints >= max(1, bilan.joursComptés - 1) {
            return "Action : conserve la même routine, elle tient bien."
        }
        return "Action : vise d'abord la régularité, pas la perfection."
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
                    .font(.welloEntête)
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
                        // Ancré à gauche : évite d'être rogné par le bord droit de la carte.
                        .annotation(position: .top, alignment: .leading, spacing: 2) {
                            Text("objectif")
                                .font(.system(.caption2, design: .rounded))
                                .foregroundStyle(WelloTheme.inkSoft)
                        }
                }
                .chartYScale(domain: 0...1.25)
                .chartYAxis(.hidden)
                .chartXAxis {
                    // Peu d'étiquettes réparties par Charts + mois abrégé (« 15 juil. » plutôt
                    // que « 15 J » ambigu) → lisible même quand les jours de données sont espacés.
                    AxisMarks(values: .automatic(desiredCount: 4)) {
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                            .font(.caption2)
                    }
                }
                // Marge de tracé : les étiquettes d'extrémité ne sont plus rognées.
                .chartPlotStyle { $0.padding(.horizontal, 8) }
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
                    .font(.welloLégendeMini)
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
                        .font(.welloEntête)
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
                .font(.welloEntête)
                .foregroundStyle(WelloTheme.ink)
            Text("Tes objectifs quotidiens apparaîtront ici au fil des jours.")
                .font(.welloProseDouce)
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
