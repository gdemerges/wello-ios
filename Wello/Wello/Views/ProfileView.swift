import SwiftUI
import SwiftData
import WelloKit

/// Édition du profil : sexe (base EFSA), état physiologique, calculs rénaux, rappels, montants rapides.
struct ProfileView: View {
    @Environment(HydrationStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Query private var profils: [UserProfile]
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(DrinkCatalog.self) private var drinks
    @Environment(ThemeStore.self) private var theme
    @State private var paywall = false

    private var profil: UserProfile? { profils.first }

    /// Sous-titre contextuel de la section Rappels selon le palier et le mode courant.
    private var sousTitreRappels: String {
        guard entitlements.isUnlocked(.adaptiveReminders) else {
            return "Rappels à heures fixes. Passe à Wello+ pour des rappels adaptés à tes habitudes."
        }
        switch store.étatRappels.mode {
        case .apprentissage:
            return "On apprend tes habitudes… (rappels classiques en attendant)."
        case .adaptatif:
            if let f = store.étatRappels.fenêtre {
                return "Rappels intelligents — basés sur tes habitudes. Fenêtre détectée ~\(f.réveilMin / 60)h–\(f.coucherMin / 60)h."
            }
            return "Rappels intelligents — basés sur tes habitudes et ta fenêtre d'éveil."
        case .fixe:
            return "Rappels intelligents — basés sur tes habitudes et ta fenêtre d'éveil."
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        paywall = true
                    } label: {
                        HStack {
                            // value = nil → `label` n'insère pas de Spacer interne ; on gère le trailing nous-mêmes.
                            label("Wello+", nil, icon: "star.fill", teinte: .yellow)
                            Spacer()
                            if entitlements.isUnlocked(.unlimitedHistory) {
                                Text("Actif")
                                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                    .foregroundStyle(.green)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                            } else {
                                Text("Débloquer tout")
                                    .font(.system(.subheadline, design: .rounded))
                                    .foregroundStyle(WelloTheme.inkSoft)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(WelloTheme.inkSoft.opacity(0.6))
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .disabled(entitlements.isUnlocked(.unlimitedHistory))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(entitlements.isUnlocked(.unlimitedHistory) ? "Wello+, actif" : "Wello+, débloquer tout")
                    .accessibilityHint(entitlements.isUnlocked(.unlimitedHistory) ? "" : "Ouvre l'offre Wello+")
                }
                themeSection
                Section {
                    if entitlements.isUnlocked(.customDrinks) {
                        ForEach(DrinkType.allCases.filter { $0 != .water }, id: \.self) { drink in
                            Stepper(value: Binding(get: { drinks.coefficient(for: drink) },
                                                   set: { drinks.setCoefficient($0, for: drink) }),
                                    in: coefficientRange, step: 0.05) {
                                HStack(spacing: 12) {
                                    Image(systemName: drink.icon)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(WelloTheme.accent)
                                        .frame(width: 30, height: 30)
                                        .background(WelloTheme.accent.opacity(0.15), in: Circle())
                                    Text(drink.label).font(.system(.body, design: .rounded))
                                    Spacer()
                                    Text(drinks.coefficient(for: drink),
                                         format: .number.precision(.fractionLength(0...2)))
                                        .font(.system(.body, design: .rounded).weight(.medium))
                                        .foregroundStyle(drinks.isCustomized(drink) ? WelloTheme.accentDeep : WelloTheme.inkSoft)
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                if drinks.isCustomized(drink) {
                                    Button("Réinitialiser") { drinks.reset(drink) }
                                }
                            }
                        }
                    } else {
                        Button {
                            paywall = true
                        } label: {
                            HStack {
                                label("Boissons personnalisées", nil,
                                      icon: "cup.and.saucer.fill", teinte: WelloTheme.accent)
                                Spacer()
                                Text("Débloquer")
                                    .font(.system(.subheadline, design: .rounded))
                                    .foregroundStyle(WelloTheme.inkSoft)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(WelloTheme.inkSoft.opacity(0.6))
                                    .accessibilityHidden(true)
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Boissons personnalisées, débloquer")
                        .accessibilityHint("Ouvre l'offre Wello+")
                    }
                } header: {
                    Text("Boissons")
                } footer: {
                    Text("Coefficient d'hydratation par boisson (eau = 1,0). Ajuste selon ton ressenti ; valeurs indicatives, non médicales.")
                        .font(.system(.caption, design: .rounded))
                }
                if let profil {
                    Section {
                        Picker(selection: Binding(get: { profil.sexe ?? .homme },
                                                  set: { profil.sexe = $0; profil.updatedAt = .now
                                                         Task { await store.refreshToday(force: true) } })) {
                            Text("Homme").tag(BiologicalSex.homme)
                            Text("Femme").tag(BiologicalSex.femme)
                        } label: {
                            label("Sexe", nil, icon: "person.fill", teinte: WelloTheme.accent)
                        }
                    } footer: {
                        Text("Fixe ta base d'hydratation selon les apports de référence EFSA (2000 ml homme / 1600 ml femme).")
                            .font(.system(.caption, design: .rounded))
                    }

                    Section {
                        Picker(selection: Binding(get: { profil.etatPhysio },
                                                  set: { profil.etatPhysio = $0; profil.updatedAt = .now
                                                         Task { await store.refreshToday(force: true) } })) {
                            Text("Aucun").tag(PhysiologicalState.aucun)
                            Text("Enceinte").tag(PhysiologicalState.grossesse)
                            Text("Allaitante").tag(PhysiologicalState.allaitement)
                        } label: {
                            label("État physiologique", nil,
                                  icon: "figure.stand", teinte: .pink)
                        }
                    } footer: {
                        Text("Ajoute l'apport recommandé (EFSA) : +300 ml enceinte, +700 ml allaitante.")
                            .font(.system(.caption, design: .rounded))
                    }

                    Section {
                        Toggle(isOn: Binding(get: { profil.renalLithiase },
                                             set: { profil.renalLithiase = $0; profil.updatedAt = .now
                                                    Task { await store.refreshToday(force: true) } })) {
                            label("Calculs rénaux (lithiase)", nil, icon: "cross.case.fill", teinte: .purple)
                        }
                        if profil.renalLithiase {
                            Stepper(value: Binding(get: { profil.renalBonusML },
                                                   set: { profil.renalBonusML = $0; profil.updatedAt = .now
                                                          Task { await store.refreshToday(force: true) } }),
                                    in: 500...1500, step: 100) {
                                label("Apport rénal", "+\(profil.renalBonusML) ml",
                                      icon: "drop.fill", teinte: .purple)
                            }
                        }
                    } footer: {
                        Text("Vise un apport plus élevé pour la prévention des calculs. À régler selon avis médical.")
                            .font(.system(.caption, design: .rounded))
                    }

                    réglageAvancéSection(profil)

                    Section {
                        Toggle(isOn: Binding(
                            get: { profil.remindersEnabled },
                            set: { actif in
                                profil.remindersEnabled = actif
                                profil.updatedAt = .now
                                // Désactivation immédiate : on annule les rappels déjà programmés.
                                if !actif { Task { await store.couperRappelsAujourdhui() } }
                            })) {
                            label("Rappels intelligents", nil, icon: "bell.fill", teinte: WelloTheme.accentDeep)
                        }
                        if !entitlements.isUnlocked(.adaptiveReminders) {
                            Button {
                                paywall = true
                            } label: {
                                HStack {
                                    label("Rappels adaptatifs", nil,
                                          icon: "sparkles", teinte: WelloTheme.accentDeep)
                                    Spacer()
                                    Text("Débloquer")
                                        .font(.system(.subheadline, design: .rounded))
                                        .foregroundStyle(WelloTheme.inkSoft)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.85)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(WelloTheme.inkSoft.opacity(0.6))
                                        .accessibilityHidden(true)
                                }
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Rappels adaptatifs, débloquer")
                            .accessibilityHint("Ouvre l'offre Wello+")
                        }
                    } footer: {
                        Text(sousTitreRappels)
                            .font(.system(.caption, design: .rounded))
                    }

                    Section {
                        stepperMontant("Bouton 1", get: { profil.quickAdd1 }, set: { profil.quickAdd1 = $0 })
                        stepperMontant("Bouton 2", get: { profil.quickAdd2 }, set: { profil.quickAdd2 = $0 })
                        stepperMontant("Bouton 3", get: { profil.quickAdd3 }, set: { profil.quickAdd3 = $0 })
                    } header: {
                        Text("Montants rapides")
                    } footer: {
                        Text("Personnalise les 3 boutons d'ajout de l'accueil.")
                            .font(.system(.caption, design: .rounded))
                    }

                    if !store.étatServices.tousOK {
                        Section {
                            diagLigne("Localisation / météo", ok: store.étatServices.météoDisponible,
                                      détailKO: "bonus météo à 0")
                            diagLigne("Notifications", ok: store.étatServices.notificationsAutorisées,
                                      détailKO: "rappels indisponibles")
                        } header: {
                            Text("Diagnostic")
                        } footer: {
                            Text("Certains services ne sont pas actifs. Tout refus est géré : l'app reste pleinement utilisable.")
                                .font(.system(.caption, design: .rounded))
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .welloBackground()
            .navigationTitle("Profil")
            .task { _ = store.profilCourant() }   // garantit l'existence d'un profil
            .sheet(isPresented: $paywall) { PaywallView() }
        }
    }

    /// Stepper d'un montant rapide (50–2000 ml, pas de 50).
    private func stepperMontant(_ titre: String, get: @escaping () -> Int,
                                set: @escaping (Int) -> Void) -> some View {
        Stepper(value: Binding(get: get, set: { set($0); profil?.updatedAt = .now }),
                in: 50...2000, step: 50) {
            label(titre, "\(get()) ml", icon: "drop.fill", teinte: WelloTheme.accent)
        }
    }

    // MARK: Réglage avancé (Wello+)

    /// Section de réglage avancé du calcul : sensibilités effort/chaleur + ajustement manuel.
    /// Débloquée en Wello+ ; sinon teasing vers le paywall.
    @ViewBuilder
    private func réglageAvancéSection(_ profil: UserProfile) -> some View {
        Section {
            if entitlements.isUnlocked(.advancedTuning) {
                multiplicateurStepper("Sensibilité à l'effort", icon: "figure.run",
                                      get: { profil.activitySensitivity },
                                      set: { profil.activitySensitivity = $0 })
                multiplicateurStepper("Sensibilité à la chaleur", icon: "thermometer.sun.fill",
                                      get: { profil.weatherSensitivity },
                                      set: { profil.weatherSensitivity = $0 })
                Stepper(value: bindingCalcul(get: { profil.manualAdjustmentML },
                                             set: { profil.manualAdjustmentML = $0 }),
                        in: -CalculatorTuning.adjustmentLimit...CalculatorTuning.adjustmentLimit, step: 50) {
                    label("Ajustement manuel", ajustementLabel(profil.manualAdjustmentML),
                          icon: "slider.horizontal.3", teinte: WelloTheme.accentDeep)
                }
                if profil.réglageAvancéModifié {
                    Button("Réinitialiser le réglage") {
                        profil.activitySensitivity = 1
                        profil.weatherSensitivity = 1
                        profil.manualAdjustmentML = 0
                        profil.updatedAt = .now
                        Task { await store.refreshToday(force: true) }
                    }
                }
            } else {
                Button {
                    paywall = true
                } label: {
                    HStack {
                        label("Réglage avancé", nil, icon: "slider.horizontal.3", teinte: WelloTheme.accentDeep)
                        Spacer()
                        Text("Débloquer")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(WelloTheme.inkSoft)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(WelloTheme.inkSoft.opacity(0.6))
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Réglage avancé, débloquer")
                .accessibilityHint("Ouvre l'offre Wello+")
            }
        } header: {
            Text("Réglage avancé")
        } footer: {
            Text("Ajuste finement ton objectif. Les plafonds de sécurité (4000 ml max) restent appliqués.")
                .font(.system(.caption, design: .rounded))
        }
    }

    /// Stepper d'un multiplicateur de sensibilité (0,5–1,5, pas de 0,1) qui recalcule l'objectif.
    private func multiplicateurStepper(_ titre: String, icon: String,
                                       get: @escaping () -> Double,
                                       set: @escaping (Double) -> Void) -> some View {
        Stepper(value: Binding(get: get, set: { nouvelle in
            // Arrondi au dixième pour éviter la dérive en virgule flottante au fil des pas.
            let arrondie = (nouvelle * 10).rounded() / 10
            set(arrondie); profil?.updatedAt = .now
            Task { await store.refreshToday(force: true) }
        }), in: CalculatorTuning.multiplierRange, step: 0.1) {
            label(titre, "×" + get().formatted(.number.precision(.fractionLength(1))),
                  icon: icon, teinte: WelloTheme.accent)
        }
    }

    /// Binding d'un réglage entier qui marque `updatedAt` et recalcule l'objectif à chaque changement.
    private func bindingCalcul(get: @escaping () -> Int, set: @escaping (Int) -> Void) -> Binding<Int> {
        Binding(get: get, set: { set($0); profil?.updatedAt = .now
                                 Task { await store.refreshToday(force: true) } })
    }

    /// Libellé signé de l'ajustement manuel ("+300 ml", "−200 ml", "0 ml").
    private func ajustementLabel(_ ml: Int) -> String {
        ml > 0 ? "+\(ml) ml" : "\(ml) ml"
    }

    /// Ligne de diagnostic : pastille verte si le service a fonctionné, sinon détail du repli.
    private func diagLigne(_ titre: String, ok: Bool, détailKO: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(ok ? .green : .orange)
            Text(titre).font(.system(.body, design: .rounded))
            Spacer()
            Text(ok ? "OK" : détailKO)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(WelloTheme.inkSoft)
        }
    }

    /// Section de choix du thème de couleur (Wello+). `glacier` gratuit ; les autres → paywall si verrouillés.
    private var themeSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(AppTheme.allCases) { t in
                        themeSwatch(t)
                    }
                }
                .padding(.vertical, 4)
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        } header: {
            Text("Thème")
        } footer: {
            Text("Personnalise la couleur de Wello. Inclus dans Wello+ (Glacier reste gratuit).")
                .font(.system(.caption, design: .rounded))
        }
    }

    /// Pastille d'un thème : disque en dégradé d'accent, coché si actif, cadenas si verrouillé.
    private func themeSwatch(_ t: AppTheme) -> some View {
        let verrouillé = !t.estGratuit && !entitlements.isUnlocked(.themes)
        let actif = theme.selected == t
        return Button {
            if verrouillé { paywall = true } else { theme.select(t) }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color(hex: t.palette.accent),
                                                      Color(hex: t.palette.accentDeep)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 44, height: 44)
                        .overlay(Circle().strokeBorder(actif ? WelloTheme.ink : .clear, lineWidth: 2.5))
                    if verrouillé {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.3), radius: 1)
                    } else if actif {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.3), radius: 1)
                    }
                }
                Text(t.label)
                    .font(.system(.caption, design: .rounded).weight(actif ? .bold : .regular))
                    .foregroundStyle(actif ? WelloTheme.ink : WelloTheme.inkSoft)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Thème \(t.label)\(verrouillé ? ", verrouillé" : "")\(actif ? ", actif" : "")")
        .accessibilityHint(verrouillé ? "Ouvre l'offre Wello+" : (actif ? "" : "Appliquer ce thème"))
    }

    /// Libellé de ligne avec pastille d'icône colorée et valeur optionnelle.
    private func label(_ titre: String, _ valeur: String?, icon: String, teinte: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(teinte)
                .frame(width: 30, height: 30)
                .background(teinte.opacity(0.15), in: Circle())
            Text(titre).font(.system(.body, design: .rounded))
            if let valeur {
                Spacer()
                Text(valeur)
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .foregroundStyle(WelloTheme.inkSoft)
            }
        }
    }
}

#if DEBUG
#Preview("Gratuit") {
    let container = PreviewSupport.container()
    return ProfileView()
        .modelContainer(container)
        .environment(PreviewSupport.store(container))
        .environment(PreviewSupport.entitlements(.free))
        .environment(PreviewSupport.drinkCatalog())
        .environment(PreviewSupport.themeStore())
}

#Preview("Wello+") {
    let container = PreviewSupport.container()
    return ProfileView()
        .modelContainer(container)
        .environment(PreviewSupport.store(container))
        .environment(PreviewSupport.entitlements(.plus))
        .environment(PreviewSupport.drinkCatalog())
        .environment(PreviewSupport.themeStore())
}
#endif
