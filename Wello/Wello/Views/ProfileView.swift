import SwiftUI
import SwiftData

/// Édition du profil : poids, plancher médical (validé ≤ 4000), rappels.
struct ProfileView: View {
    @Environment(HydrationStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Query private var profils: [UserProfile]

    private var profil: UserProfile? { profils.first }

    var body: some View {
        NavigationStack {
            Form {
                if let profil {
                    Section {
                        Stepper(value: Binding(get: { profil.weightKg },
                                               set: { profil.weightKg = $0; profil.updatedAt = .now }),
                                in: 30...250, step: 0.5) {
                            label("Poids", String(format: "%.1f kg", profil.weightKg), icon: "scalemass.fill", teinte: WelloTheme.accent)
                        }
                    }

                    Section {
                        Stepper(value: Binding(get: { profil.medicalFloorML },
                                               set: { profil.medicalFloorML = min($0, 4000); profil.updatedAt = .now }),
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
                }
            }
            .scrollContentBackground(.hidden)
            .welloBackground()
            .navigationTitle("Profil")
            .task { _ = store.profilCourant() }   // garantit l'existence d'un profil
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
}
#endif
