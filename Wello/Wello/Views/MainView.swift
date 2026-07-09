import SwiftUI
import SwiftData
import WelloKit

/// Écran principal : jauge « verre d'eau », boutons de log rapide et détail de l'objectif.
struct MainView: View {
    /// Vrai quand l'onglet « Aujourd'hui » est au premier plan → anime la jauge (sinon en pause).
    var estActif: Bool = true
    @Environment(HydrationStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Tous les logs (tri récent→ancien) ; on filtre « aujourd'hui » à l'affichage pour rester
    /// correct au passage de minuit sans prédicat figé à l'init.
    @Query(sort: \HydrationLog.loggedAt, order: .reverse) private var tousLogs: [HydrationLog]
    @Query(sort: \DailyGoal.date, order: .reverse) private var objectifs: [DailyGoal]
    @Query private var profils: [UserProfile]
    /// Reflète l'état « rappels coupés pour aujourd'hui » (retour visuel de la cloche).
    @State private var rappelsCoupésAujourdhui = false
    @State private var afficheSaisie = false
    @State private var fête = false
    @State private var messageFête = "Objectif atteint ! 🎉"
    @State private var fêteEstPalier = false

    private var logsDuJour: [HydrationLog] {
        tousLogs.filter { Calendar.current.isDateInToday($0.loggedAt) }
    }
    private var consommé: Int { clampedDayTotal(logsDuJour.reduce(0) { $0 + $1.effectiveML }) }
    private var objectif: Int { store.breakdown?.totalML ?? 0 }
    private var objectifAtteint: Bool { objectif > 0 && consommé >= objectif }
    private var montants: [Int] { profils.first?.quickAdds ?? [150, 250, 500] }

    /// Série d'objectifs atteints en cours, aujourd'hui compris s'il est atteint.
    /// On compte les jours passés (contigus, récent→ancien) à partir des `DailyGoal`, puis on
    /// ajoute aujourd'hui si l'objectif du jour est atteint. Fonction pure déléguée à WelloKit.
    private var sérieCourante: Int {
        let cal = Calendar.current
        var conso: [Date: Int] = [:]
        for log in tousLogs { conso[cal.startOfDay(for: log.loggedAt), default: 0] += log.effectiveML }
        let aujourdhui = cal.startOfDay(for: .now)
        let passés = objectifs.compactMap { g -> DailyTotal? in
            let d = cal.startOfDay(for: g.date)
            guard d < aujourdhui else { return nil }
            return DailyTotal(consumedML: clampedDayTotal(conso[d] ?? 0), goalML: g.totalML)
        }
        return HydrationStats.currentStreak(passés) + (objectifAtteint ? 1 : 0)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    WaterGaugeView(consomméML: consommé, objectifML: objectif, animer: estActif)
                        .padding(.top, 8)

                    if objectif > 0 {
                        RhythmCard(pace: HydrationPaceCalculator.evaluate(
                            goalML: objectif,
                            consumedML: consommé,
                            now: .now,
                            window: store.étatRappels.fenêtre ?? .défaut
                        ))
                        .padding(.horizontal)
                    }

                    HStack(spacing: 14) {
                        ForEach(Array(montants.enumerated()), id: \.offset) { _, ml in
                            WaterLogButton(ml: ml) { await store.log(ml: ml) }
                        }
                        WaterMorePill { afficheSaisie = true }
                    }
                    .padding(.horizontal)

                    if sérieCourante >= 2 {
                        StreakChip(jours: sérieCourante)
                    }

                    if let dernière = logsDuJour.first {
                        Button {
                            Task { await store.annulerDernièrePrise() }
                        } label: {
                            Label("Annuler la dernière prise (+\(dernière.amountML) ml)",
                                  systemImage: "arrow.uturn.backward")
                                .font(.system(.subheadline, design: .rounded))
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
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
                                      météoIndisponible: store.météoIndisponible,
                                      libelléÉtatPhysio: profils.first.flatMap { $0.etatPhysio == .aucun ? nil : $0.etatPhysio.label })
                            .padding(.horizontal)
                        SourcesFreshnessCard(état: store.étatSources,
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
                                await store.refreshToday(force: true)   // réactive et replanifie
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
                SaisieEauSheet { ml, drink, coeff in
                    Task { await store.log(ml: ml, drink: drink, coefficient: coeff) }
                }
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
            Label(messageFête, systemImage: fêteEstPalier ? "flame.fill" : "checkmark.seal.fill")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(fêteEstPalier ? AnyShapeStyle(orangeGradient) : AnyShapeStyle(WelloTheme.accentGradient),
                            in: Capsule())
                .shadow(color: (fêteEstPalier ? Color.orange : WelloTheme.accent).opacity(0.4), radius: 10, y: 4)
                .padding(.top, 8)
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
        }
    }

    /// Dégradé chaud réservé aux célébrations de paliers de série.
    private var orangeGradient: LinearGradient {
        LinearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func déclencherFête() {
        // Une série qui atteint pile un palier (7, 30, 100… jours) déclenche une célébration renforcée.
        if let palier = StreakMilestone.palier(pour: sérieCourante) {
            messageFête = "\(palier) jours d'affilée ! 🔥"
            fêteEstPalier = true
            AccessibilityNotification.Announcement("Série de \(palier) jours d'affilée atteinte").post()
        } else {
            messageFête = "Objectif atteint ! 🎉"
            fêteEstPalier = false
            AccessibilityNotification.Announcement("Objectif d'hydratation atteint").post()
        }
        let apparition: Animation = reduceMotion ? .easeInOut(duration: 0.25) : .spring(response: 0.4, dampingFraction: 0.7)
        withAnimation(apparition) { fête = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(fêteEstPalier ? 3.2 : 2.5))
            withAnimation(.easeOut(duration: 0.5)) { fête = false }
        }
    }
}

/// Carte de rythme intra-journée : transforme l'objectif restant en action concrète.
private struct RhythmCard: View {
    let pace: HydrationPace

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(teinte)
                        .frame(width: 34, height: 34)
                        .background(teinte.opacity(0.15), in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rythme du jour")
                            .font(.welloEntête)
                            .foregroundStyle(WelloTheme.ink)
                        Text(message)
                            .font(.welloProseDouce)
                            .foregroundStyle(WelloTheme.inkSoft)
                    }
                }

                HStack(spacing: 12) {
                    metric("\(pace.expectedNowML) ml", "attendus maintenant")
                    metric("\(pace.remainingML) ml", "restants")
                    metric("\(pace.glassesToGo)", pace.glassesToGo <= 1 ? "verre" : "verres")
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var message: LocalizedStringKey {
        switch pace.status {
        case .notStarted:
            "La journée démarre doucement. Ton rythme commencera à l'heure d'éveil."
        case .onTrack:
            "Tu es dans le bon rythme. Continue par petites prises régulières."
        case .behind:
            "Tu es un peu en retard : vise un verre maintenant, puis reprends tranquillement."
        case .ahead:
            "Tu as de l'avance. Garde le rythme sans forcer."
        case .done:
            "Objectif atteint. Le reste de la journée peut rester léger."
        }
    }

    private var icon: String {
        switch pace.status {
        case .behind: "clock.badge.exclamationmark"
        case .ahead: "forward.fill"
        case .done: "checkmark.seal.fill"
        default: "clock.fill"
        }
    }

    private var teinte: Color {
        switch pace.status {
        case .behind: .orange
        case .ahead: .green
        case .done: .green
        default: WelloTheme.accent
        }
    }

    private func metric(_ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(WelloTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.welloLégendeMini)
                .foregroundStyle(WelloTheme.inkSoft)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Carte de confiance : affiche la fraîcheur des sources qui alimentent l'objectif du jour.
private struct SourcesFreshnessCard: View {
    let état: ÉtatSourcesHydratation
    let météoIndisponible: Bool
    @State private var détail = false

    private var sourcesOK: Int {
        [état.objectifCalculéÀ, état.énergieLueÀ, état.météoCapturéeÀ, état.importsSantéLusÀ]
            .filter { $0 != nil }
            .count
    }

    var body: some View {
        Button { détail = true } label: {
            CardContainer {
                HStack(spacing: 12) {
                    Image(systemName: météoIndisponible ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(météoIndisponible ? .orange : .green)
                        .frame(width: 34, height: 34)
                        .background((météoIndisponible ? Color.orange : Color.green).opacity(0.14), in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sources du jour")
                            .font(.welloEntête)
                            .foregroundStyle(WelloTheme.ink)
                        Text(résumé)
                            .font(.welloProseDouce)
                            .foregroundStyle(WelloTheme.inkSoft)
                            .lineLimit(2)
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
        .accessibilityHint("Voir le détail des sources")
        .sheet(isPresented: $détail) {
            NavigationStack {
                List {
                    Section {
                        sourceRow("Objectif", icon: "target", date: état.objectifCalculéÀ,
                                  fallback: "pas encore calculé")
                        sourceRow("Énergie HealthKit", icon: "figure.run", date: état.énergieLueÀ,
                                  fallback: "non lue")
                        sourceRow("Météo", icon: météoIndisponible ? "wifi.slash" : "cloud.sun.fill",
                                  date: état.météoCapturéeÀ,
                                  fallback: météoIndisponible ? "indisponible" : "non capturée")
                        sourceRow("Eau depuis Santé", icon: "heart.fill", date: état.importsSantéLusÀ,
                                  fallback: "non lue",
                                  suffix: état.importsSantéAjoutés > 0 ? "+\(état.importsSantéAjoutés) import(s)" : "aucun nouvel import")
                    } footer: {
                        Text("Ces horaires indiquent la dernière lecture locale utilisée par Wello. En cas de refus, l'app garde un repli neutre et reste utilisable.")
                            .font(.welloLégendeMini)
                    }
                }
                .scrollContentBackground(.hidden)
                .welloBackground()
                .navigationTitle("Sources du jour")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("OK") { détail = false }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private var résumé: LocalizedStringKey {
        if météoIndisponible {
            return "\(sourcesOK)/4 sources lues — météo indisponible"
        }
        if sourcesOK == 4 {
            return "Toutes les sources ont été lues"
        }
        return "\(sourcesOK)/4 sources lues"
    }

    private func sourceRow(_ title: LocalizedStringKey, icon: String, date: Date?,
                           fallback: LocalizedStringKey, suffix: String? = nil) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WelloTheme.accent)
                .frame(width: 30, height: 30)
                .background(WelloTheme.accent.opacity(0.15), in: Circle())
                .accessibilityHidden(true)
            Text(title)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(WelloTheme.ink)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                if let date {
                    Text("à \(date.formatted(.dateTime.hour().minute()))")
                        .font(.welloLégendeMini)
                        .foregroundStyle(WelloTheme.inkSoft)
                } else {
                    Text(fallback)
                        .font(.welloLégendeMini)
                        .foregroundStyle(WelloTheme.inkSoft)
                }
                if let suffix {
                    Text(suffix)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(WelloTheme.inkSoft.opacity(0.85))
                }
            }
        }
    }
}

/// Pastille « série en cours » affichée sous les boutons d'ajout (gratuit, moteur de rétention).
private struct StreakChip: View {
    let jours: Int
    var body: some View {
        Label("\(jours) jours d'affilée", systemImage: "flame.fill")
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(.orange.opacity(0.12), in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Série en cours : \(jours) jours d'affilée")
    }
}

/// Feuille de saisie d'une prise : eau seule en gratuit (+ teasing), choix de la boisson en Wello+.
private struct SaisieEauSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(DrinkCatalog.self) private var drinks
    @State private var ml = 300
    @State private var drink: DrinkType = .water
    @State private var paywall = false
    /// (volume, boisson, coefficient snapshoté).
    let onConfirm: (Int, DrinkType, Double) -> Void

    private var premium: Bool { entitlements.isUnlocked(.customDrinks) }
    private var coefficient: Double { drinks.coefficient(for: drink) }
    private var effectif: Int { effectiveHydrationML(volumeML: ml, coefficient: coefficient) }

    var body: some View {
        NavigationStack {
            Form {
                if premium {
                    Section {
                        Picker(selection: $drink) {
                            ForEach(DrinkType.allCases, id: \.self) { d in
                                Label(d.label, systemImage: d.icon).tag(d)
                            }
                        } label: {
                            Text("Boisson").font(.system(.body, design: .rounded))
                        }
                    }
                }
                Section {
                    Stepper(value: $ml, in: 10...3000, step: 10) {
                        HStack {
                            Text("Quantité").font(.system(.body, design: .rounded))
                            Spacer()
                            Text("\(ml) ml")
                                .font(.system(.body, design: .rounded).weight(.medium))
                                .foregroundStyle(WelloTheme.inkSoft)
                        }
                    }
                } footer: {
                    if premium && coefficient != 1.0 {
                        Text("≈ \(effectif) ml hydratants (coefficient \(coefficient, format: .number.precision(.fractionLength(0...2))))")
                            .font(.system(.caption, design: .rounded))
                    }
                }
                if !premium {
                    Section {
                        PremiumGateCard(bénéfice: "Café, thé, alcool… au-delà de l'eau") {
                            paywall = true
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .welloBackground()
            .navigationTitle(premium ? "Ajouter une boisson" : "Ajouter de l'eau")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") {
                        onConfirm(ml, premium ? drink : .water, premium ? coefficient : 1.0)
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $paywall) {
                PaywallView(bénéfice: "Bois ce que tu veux, compté juste")
            }
        }
        .presentationDetents([.height(premium ? 320 : 240)])
    }
}

#if DEBUG
#Preview {
    let container = PreviewSupport.container()
    return MainView()
        .modelContainer(container)
        .environment(PreviewSupport.store(container))
        .environment(PreviewSupport.entitlements(.plus))
        .environment(PreviewSupport.drinkCatalog())
}
#endif
