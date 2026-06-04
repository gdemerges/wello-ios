import SwiftUI
import SwiftData

/// Édition du profil : poids, plancher médical (validé ≤ 4000), rappels.
struct ProfileView: View {
    @Environment(HydrationStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Query private var profils: [UserProfile]
    @Environment(EntitlementStore.self) private var entitlements
    @State private var paywall = false

    private var profil: UserProfile? { profils.first }

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
                            } else {
                                Text("Débloquer tout")
                                    .font(.system(.subheadline, design: .rounded))
                                    .foregroundStyle(WelloTheme.inkSoft)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(WelloTheme.inkSoft.opacity(0.6))
                            }
                        }
                    }
                    .disabled(entitlements.isUnlocked(.unlimitedHistory))
                }
                if let profil {
                    Section {
                        Stepper(value: Binding(get: { profil.weightKg },
                                               set: { profil.weightKg = $0; profil.updatedAt = .now
                                                      Task { await store.refreshToday(force: true) } }),
                                in: 30...250, step: 0.5) {
                            label("Poids", String(format: "%.1f kg", profil.weightKg), icon: "scalemass.fill", teinte: WelloTheme.accent)
                        }
                    }

                    Section {
                        Stepper(value: Binding(get: { profil.medicalFloorML },
                                               set: { profil.medicalFloorML = min($0, 4000); profil.updatedAt = .now
                                                      Task { await store.refreshToday(force: true) } }),
                                in: 1000...4000, step: 100) {
                            label("Plancher médical", "\(profil.medicalFloorML) ml", icon: "cross.case.fill", teinte: .pink)
                        }
                    } footer: {
                        Text("Plafonné à 4000 ml pour éviter toute hyperhydratation.")
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
                            diagLigne("Santé (poids)", ok: store.étatServices.poidsDepuisSanté,
                                      détailKO: "poids depuis le profil")
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
#Preview {
    let container = PreviewSupport.container()
    return ProfileView()
        .modelContainer(container)
        .environment(PreviewSupport.store(container))
        .environment(PreviewSupport.entitlements(.free))
}
#endif
