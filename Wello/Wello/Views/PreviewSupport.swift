#if DEBUG
import SwiftUI
import SwiftData

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
        ctx.insert(UserProfile(weightKg: 78, medicalFloorML: 2500))
        ctx.insert(HydrationLog(amountML: 250))
        ctx.insert(HydrationLog(amountML: 500))

        let hier = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        ctx.insert(DailyGoal(date: Calendar.current.startOfDay(for: hier),
                             baseML: 2730, activityBonusML: 300, weatherBonusML: 500,
                             medicalFloorML: 2500, totalML: 3530))
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
}
#endif
