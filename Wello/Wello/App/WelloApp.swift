import SwiftUI
import SwiftData
import UserNotifications
import WelloKit

@main
struct WelloApp: App {
    /// Conteneur SwiftData pour les 3 modèles.
    let container: ModelContainer
    @State private var store: HydrationStore
    @State private var entitlements: EntitlementStore
    @State private var drinks: DrinkCatalog
    @State private var theme: ThemeStore
    /// Délégué des notifications, retenu ici (la propriété `delegate` du centre est faible).
    private let notifDelegate: NotificationCoordinator

    init() {
        let container = WelloShared.makeModelContainer()
        self.container = container
        // Services réels injectés dans l'orchestrateur.
        let entitlements = EntitlementStore(store: StoreKitService())
        let watchSync = WatchConnectivityService()
        let store = HydrationStore(
            modelContext: container.mainContext,
            healthKit: HealthKitService(),
            weather: WeatherService(),
            location: LocationService(),
            notifications: NotificationService(),
            watchSync: watchSync,
            rappelsAdaptatifsDébloqués: { entitlements.isUnlocked(.adaptiveReminders) }
        )
        // Prises saisies au poignet : ingérées par le store (sur le MainActor).
        watchSync.onPriseDistante = { [store] prise in
            Task { @MainActor in await store.enregistrerPriseDistante(prise) }
        }
        _store = State(initialValue: store)
        _entitlements = State(initialValue: entitlements)
        _drinks = State(initialValue: DrinkCatalog())
        _theme = State(initialValue: ThemeStore())

        // Délégué des notifications branché sur le même store (actions directes).
        let delegate = NotificationCoordinator(store: store)
        self.notifDelegate = delegate
        UNUserNotificationCenter.current().delegate = delegate
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(entitlements)
                .environment(drinks)
                .environment(theme)
                .task {
                    await entitlements.démarrer()
                    theme.enforceEntitlement(unlocked: entitlements.isUnlocked(.themes))
                    // Séances et prises d'eau externes réveillent l'app même fermée : l'objectif,
                    // les rappels, le widget et la Live Activity suivent une séance du soir sans
                    // attendre la prochaine ouverture. (Ré)enregistré à chaque lancement.
                    store.démarrerObservationSanté()
                }
        }
        .modelContainer(container)
    }
}
