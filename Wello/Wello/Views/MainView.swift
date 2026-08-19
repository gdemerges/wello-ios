import SwiftUI
import SwiftData
import StoreKit
import WelloKit

/// Écran principal : jauge « verre d'eau », boutons de log rapide et détail de l'objectif.
struct MainView: View {
    /// Vrai quand l'onglet « Aujourd'hui » est au premier plan → anime la jauge (sinon en pause).
    var estActif: Bool = true
    @Environment(HydrationStore.self) private var store
    @Environment(ReviewPrompter.self) private var avis
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.requestReview) private var demanderAvis
    /// Prises depuis le début de la journée d'ouverture (tri récent→ancien) : le prédicat borne
    /// le chargement, et le filtre « aujourd'hui » à l'affichage garde l'écran correct si l'app
    /// reste ouverte au passage de minuit (la veille est alors chargée, mais pas comptée).
    @Query private var logsRécents: [HydrationLog]
    @Query private var profils: [UserProfile]
    @State private var afficheSaisie = false
    @State private var fête = false
    @State private var messageFête = "Objectif atteint ! 🎉"
    @State private var fêteEstPalier = false

    init(estActif: Bool = true) {
        self.estActif = estActif
        let début = Calendar.current.startOfDay(for: .now)
        _logsRécents = Query(filter: #Predicate<HydrationLog> { $0.loggedAt >= début },
                             sort: \.loggedAt, order: .reverse)
    }

    private var logsDuJour: [HydrationLog] {
        logsRécents.filter { Calendar.current.isDateInToday($0.loggedAt) }
    }
    private var consommé: Int { clampedDayTotal(logsDuJour.reduce(0) { $0 + $1.effectiveML }) }
    private var objectif: Int { store.breakdown?.totalML ?? 0 }
    private var objectifAtteint: Bool { objectif > 0 && consommé >= objectif }
    private var montants: [Int] { profils.first?.quickAdds ?? [150, 250, 500] }

    /// Série d'objectifs atteints en cours, aujourd'hui compris s'il est atteint. Calculée et
    /// mémoïsée par le store à chaque prise (l'écran ne recharge plus l'historique pour l'obtenir).
    private var sérieCourante: Int { store.sérieCourante }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    // Héros composé : jauge + voix d'état serrées ensemble (une seule unité visuelle).
                    VStack(spacing: 18) {
                        WaterGaugeView(consomméML: consommé, objectifML: objectif, animer: estActif)

                        if objectif > 0 {
                            RythmeSection(goalML: objectif, consumedML: consommé,
                                          fenêtre: store.étatRappels.fenêtre ?? .défaut)
                                .padding(.horizontal, 28)
                        }
                    }
                    .padding(.top, 8)

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

                    if store.rappelsCoupésAujourdhui {
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
                            if store.rappelsCoupésAujourdhui {
                                await store.réactiverRappelsAujourdhui()
                            } else {
                                await store.couperRappelsAujourdhui()
                            }
                        }
                    } label: {
                        Label(store.rappelsCoupésAujourdhui ? "Réactiver les rappels" : "Couper les rappels aujourd'hui",
                              systemImage: store.rappelsCoupésAujourdhui ? "bell.slash.fill" : "bell")
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
        // Le compteur avance à chaque objectif atteint ; la règle (WelloKit) décide s'il faut
        // solliciter un avis. On attend la fin de la bannière pour ne pas superposer deux
        // évènements : la fête d'abord, l'invite système ensuite.
        let solliciterAvis = avis.objectifAtteint()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(fêteEstPalier ? 3.2 : 2.5))
            withAnimation(.easeOut(duration: 0.5)) { fête = false }
            guard solliciterAvis else { return }
            try? await Task.sleep(for: .seconds(0.8))
            demanderAvis()
        }
    }
}

/// Voix d'état du jour, sous la jauge : la seule phrase en serif de l'écran (« Au fil de
/// l'eau. », « Belle avance. »…) + la barre de rythme nue — sans carte, sans icône-cerclée.
/// La typographie porte le jugement ; la barre porte la position ; la teinte porte l'urgence.
/// `TimelineView(.everyMinute)` réévalue le rythme même si aucune donnée ne change : le repère
/// « maintenant » avance avec l'heure (avant, il restait figé tant que le body ne changeait pas).
private struct RythmeSection: View {
    let goalML: Int
    let consumedML: Int
    let fenêtre: FenêtreÉveil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            contenu(pace: HydrationPaceCalculator.evaluate(goalML: goalML, consumedML: consumedML,
                                                           now: timeline.date, window: fenêtre))
        }
    }

    private func contenu(pace: HydrationPace) -> some View {
        VStack(spacing: 12) {
            Text(phrase(pace.status))
                .font(.welloTitre3)
                .foregroundStyle(pace.status == .done ? WelloTheme.success : WelloTheme.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 8) {
                barre(pace: pace)
                // À l'objectif atteint, la phrase serif porte déjà le message : la barre pleine
                // suffit comme clôture, pas de légende redondante.
                if pace.status != .done {
                    légende(pace: pace)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilité(pace))
    }

    /// Fraction bue de l'objectif (remplissage de la barre), bornée 0…1.
    private var fractionBue: Double {
        guard goalML > 0 else { return 0 }
        return min(1, max(0, Double(consumedML) / Double(goalML)))
    }

    /// Barre nue : piste neutre, remplissage teinté (= bu), fin repère sombre (= attendu maintenant).
    private func barre(pace: HydrationPace) -> some View {
        let teinte = teinte(pace.status)
        let fractionMaintenant = goalML > 0
            ? min(1, max(0, Double(pace.expectedNowML) / Double(goalML))) : 0
        return GeometryReader { geo in
            let largeur = geo.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(WelloTheme.inkSoft.opacity(0.15))
                Capsule()
                    .fill(LinearGradient(colors: [teinte.opacity(0.85), teinte],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(fractionBue > 0 ? 10 : 0, largeur * fractionBue))
                if pace.status != .done {
                    Capsule()
                        .fill(WelloTheme.ink)
                        .frame(width: 3, height: 18)
                        .overlay(Capsule().stroke(WelloTheme.card, lineWidth: 1))
                        .offset(x: min(largeur - 3, max(0, largeur * fractionMaintenant - 1.5)))
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(height: 10)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: fractionBue)
    }

    /// Légende sous la barre : à gauche l'explication du repère, à droite le reste à boire.
    private func légende(pace: HydrationPace) -> some View {
        HStack(spacing: 6) {
            Text("maintenant")
            Spacer(minLength: 8)
            Text("reste \(pace.remainingML) ml")
                .foregroundStyle(WelloTheme.ink)
        }
        .font(.welloLégendeMini)
        .foregroundStyle(WelloTheme.inkSoft)
    }

    /// La voix éditoriale : courte, aquatique, jamais culpabilisante.
    private func phrase(_ status: HydrationPaceStatus) -> LocalizedStringKey {
        switch status {
        case .notStarted: "La journée se lève."
        case .onTrack:    "Au fil de l'eau."
        case .ahead:      "Belle avance."
        case .behind:     "Un verre pour revenir à flot ?"
        case .done:       "Objectif atteint"
        }
    }

    private func accessibilité(_ pace: HydrationPace) -> LocalizedStringKey {
        switch pace.status {
        case .done: "Rythme du jour : objectif atteint."
        default: "Rythme du jour : il reste \(pace.remainingML) ml à boire."
        }
    }

    private func teinte(_ status: HydrationPaceStatus) -> Color {
        switch status {
        case .behind: .orange
        case .ahead, .done: WelloTheme.success
        default: WelloTheme.accent
        }
    }
}

/// Ligne de confiance : la fraîcheur des sources en une ligne discrète (palier « méta »,
/// texte nu — plus une carte à hauteur des vraies informations). Le détail reste en feuille.
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
            HStack(spacing: 7) {
                Circle()
                    .fill(météoIndisponible ? Color.orange : WelloTheme.success)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
                Text(résumé)
                    .font(.welloLégendeMini)
                    .foregroundStyle(WelloTheme.inkSoft)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(WelloTheme.inkSoft.opacity(0.55))
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)          // zone tactile pleine malgré la discrétion visuelle
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sources du jour")
        .accessibilityValue(résumé)
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
/// Métaphore aquatique (vague continue) plutôt que la flamme Duolingo : la régularité, c'est
/// l'eau qui coule sans interruption — cohérent avec l'univers de l'app.
private struct StreakChip: View {
    let jours: Int
    var body: some View {
        Label("\(jours) jours d'affilée", systemImage: "water.waves")
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .foregroundStyle(WelloTheme.accentDeep)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(WelloTheme.accent.opacity(0.12), in: Capsule())
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

    /// Micro-pédagogie sur l'effet réel de la boisson choisie : une boisson n'hydrate pas toujours
    /// à 100 %, certaines ne comptent pas, d'autres retirent de l'eau (spiritueux). Rendu coloré
    /// pour que la nuance saute aux yeux au moment de valider la prise.
    @ViewBuilder private var effetHydratation: some View {
        let pourcent = Int((coefficient * 100).rounded())
        if coefficient < 0 {
            effetLigne("exclamationmark.triangle.fill", .orange,
                       "Boisson déshydratante — retranche ≈ \(-effectif) ml de ton total.")
        } else if coefficient == 0 {
            effetLigne("minus.circle.fill", WelloTheme.inkSoft,
                       "N'hydrate pas — comptée pour 0 ml.")
        } else if coefficient < 1 {
            effetLigne("drop.fill", WelloTheme.inkSoft,
                       "Hydrate à \(pourcent) % — ≈ \(effectif) ml comptés sur \(ml).")
        } else {
            effetLigne("drop.fill", WelloTheme.accentDeep,
                       "≈ \(effectif) ml comptés.")
        }
    }

    private func effetLigne(_ icon: String, _ teinte: Color, _ texte: LocalizedStringKey) -> some View {
        Label { Text(texte) } icon: { Image(systemName: icon).foregroundStyle(teinte) }
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(teinte)
    }

    var body: some View {
        NavigationStack {
            Form {
                if premium {
                    Section {
                        Picker(selection: $drink) {
                            ForEach(DrinkType.allCases, id: \.self) { d in
                                Label(d.libellé, systemImage: d.icon).tag(d)
                            }
                        } label: {
                            Text("Boisson").font(.system(.body, design: .rounded))
                        }
                    }
                }
                Section {
                    // Presets des contenants courants : un tap au lieu de dizaines de crans de
                    // stepper (verre, canette, bouteille…). Le stepper reste pour l'ajustement fin.
                    FlowLayout(spacing: 8) {
                        ForEach([100, 150, 250, 330, 500, 750, 1000], id: \.self) { préréglé in
                            Button {
                                ml = préréglé
                            } label: {
                                Text("\(préréglé)")
                                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                    .foregroundStyle(ml == préréglé ? .white : WelloTheme.accentDeep)
                                    .padding(.horizontal, 13)
                                    .padding(.vertical, 8)
                                    .background(ml == préréglé ? AnyShapeStyle(WelloTheme.accentDeep)
                                                               : AnyShapeStyle(WelloTheme.accent.opacity(0.12)),
                                                in: Capsule())
                                    .contentShape(Rectangle().inset(by: -5))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(préréglé) millilitres")
                            .accessibilityAddTraits(ml == préréglé ? .isSelected : [])
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))

                    Stepper(value: $ml, in: 10...3000, step: 10) {
                        HStack {
                            Text("Quantité").font(.system(.body, design: .rounded))
                            Spacer()
                            Text("\(ml) ml")
                                .font(.system(.body, design: .rounded).weight(.medium))
                                .foregroundStyle(WelloTheme.inkSoft)
                                .contentTransition(.numericText())
                        }
                    }
                } footer: {
                    if premium && coefficient != 1.0 {
                        effetHydratation
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
        // Hauteur : +~110 pt pour la rangée de presets (2 lignes de chips au max).
        .presentationDetents([.height(premium ? 430 : 350)])
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
        .environment(PreviewSupport.reviewPrompter())
}
#endif
