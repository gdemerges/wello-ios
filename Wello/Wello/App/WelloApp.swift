import SwiftUI
import SwiftData
import UserNotifications

@main
struct WelloApp: App {
    /// Conteneur SwiftData pour les 3 modèles.
    let container: ModelContainer
    @State private var store: HydrationStore
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

        // Délégué des notifications branché sur le même store (actions directes).
        let delegate = NotificationCoordinator(store: store)
        self.notifDelegate = delegate
        UNUserNotificationCenter.current().delegate = delegate
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                MainView()
                    .tabItem { Label("Aujourd'hui", systemImage: "drop.fill") }
                HistoryView()
                    .tabItem { Label("Historique", systemImage: "calendar") }
                ProfileView()
                    .tabItem { Label("Profil", systemImage: "person.fill") }
            }
            .environment(store)
        }
        .modelContainer(container)
    }
}
