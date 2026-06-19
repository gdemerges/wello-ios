import SwiftUI

@main
struct WelloWatchApp: App {
    @State private var store = WatchStore()

    var body: some Scene {
        WindowGroup {
            NavigationStack { WatchMainView() }
                .environment(\.locale, Locale(identifier: "fr_FR"))
                .environment(store)
        }
    }
}
