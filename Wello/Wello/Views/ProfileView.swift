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
                    Section("Poids") {
                        Stepper(value: Binding(get: { profil.weightKg },
                                               set: { profil.weightKg = $0; profil.updatedAt = .now }),
                                in: 30...250, step: 0.5) {
                            Text("\(profil.weightKg, specifier: "%.1f") kg")
                        }
                    }
                    Section("Plancher médical") {
                        Stepper(value: Binding(get: { profil.medicalFloorML },
                                               set: { profil.medicalFloorML = min($0, 4000); profil.updatedAt = .now }),
                                in: 1000...4000, step: 100) {
                            Text("\(profil.medicalFloorML) ml")
                        }
                        Text("Plafonné à 4000 ml pour éviter toute hyperhydratation.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Rappels") {
                        Toggle("Rappels intelligents", isOn: Binding(
                            get: { profil.remindersEnabled },
                            set: { actif in
                                profil.remindersEnabled = actif
                                profil.updatedAt = .now
                                // Désactivation immédiate : on annule les rappels déjà programmés.
                                if !actif { Task { await store.couperRappelsAujourdhui() } }
                            }))
                    }
                }
            }
            .navigationTitle("Profil")
            .task { _ = store.profilCourant() }   // garantit l'existence d'un profil
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
