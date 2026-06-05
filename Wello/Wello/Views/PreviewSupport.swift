#if DEBUG
import SwiftUI
import SwiftData
import WelloKit

/// Outils partagés pour les SwiftUI Previews : conteneur SwiftData en mémoire (données
/// d'exemple) + `HydrationStore` branché sur les mocks. Permet de prévisualiser les écrans
/// en live, sans device ni HealthKit/réseau. Compilé uniquement en DEBUG.
@MainActor
enum PreviewSupport {
    /// Conteneur en mémoire avec un profil, deux prises d'eau et un objectif d'hier.
    static func container() -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: UserProfile.self, DailyGoal.self, HydrationLog.self,
                                            configurations: config)
        let ctx = container.mainContext
        let profil = UserProfile()
        profil.sexe = .homme
        ctx.insert(profil)
        ctx.insert(HydrationLog(amountML: 250))
        ctx.insert(HydrationLog(amountML: 500))
        ctx.insert(HydrationLog(amountML: 250, drinkType: "coffee", coefficient: 0.8))

        let hier = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        ctx.insert(DailyGoal(date: Calendar.current.startOfDay(for: hier),
                             baseML: 2000, activityBonusML: 300, weatherBonusML: 500,
                             lifeStageBonusML: 0, renalBonusML: 0, totalML: 2800))
        return container
    }

    /// Store sur mocks, pour des previews réalistes (objectif calculé, jauge remplie).
    static func store(_ container: ModelContainer) -> HydrationStore {
        HydrationStore(modelContext: container.mainContext,
                       healthKit: MockHealthKitService(),
                       weather: MockWeatherService(),
                       location: MockLocationService(),
                       notifications: MockNotificationService())
    }

    /// EntitlementStore sur mock, pour prévisualiser l'UI premium (free par défaut).
    static func entitlements(_ statut: EntitlementStatus = .free) -> EntitlementStore {
        EntitlementStore(store: MockStoreService(statut: statut))
    }

    /// Catalogue de boissons sur un domaine UserDefaults éphémère (previews isolées du réel).
    static func drinkCatalog() -> DrinkCatalog {
        DrinkCatalog(defaults: UserDefaults(suiteName: "preview.drinks") ?? .standard)
    }
}
#endif
