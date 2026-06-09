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
}

#Preview("Wello+") {
    let container = PreviewSupport.container()
    return ProfileView()
        .modelContainer(container)
        .environment(PreviewSupport.store(container))
        .environment(PreviewSupport.entitlements(.plus))
        .environment(PreviewSupport.drinkCatalog())
}
#endif
