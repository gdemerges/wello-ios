import SwiftUI
import SwiftData
import UserNotifications

@main
struct WelloApp: App {
    /// Conteneur SwiftData pour les 3 modèles.
    let container: ModelContainer
    @State private var store: HydrationStore
    @State private var entitlements: EntitlementStore
    /// Délégué des notifications, retenu ici (la propriété `delegate` du centre est faible).
    private let notifDelegate: NotificationCoordinator

    init() {
        let container = try! ModelContainer(for: UserProfile.self, DailyGoal.self, HydrationLog.self)
        self.container = container
        // Services réels injectés dans l'orchestrateur.
        let store = HydrationStore(
            modelContext: container.mainContext,
            healthKit: HealthKitService(),
            weather: WeatherService(),
            location: LocationService(),
            notifications: NotificationService()
        )
        _store = State(initialValue: store)
        _entitlements = State(initialValue: EntitlementStore(store: StoreKitService()))

        // Délégué des notifications branché sur le même store (actions directes).
        let delegate = NotificationCoordinator(store: store)
        self.notifDelegate = delegate
        UNUserNotificationCenter.current().delegate = delegate
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.locale, Locale(identifier: "fr_FR"))   // app francophone : dates/nombres en FR
                .environment(store)
                .environment(entitlements)
                .task { await entitlements.démarrer() }
        }
        .modelContainer(container)
    }
}
