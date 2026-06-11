import WidgetKit
import SwiftUI

/// Point d'entrée de l'extension widget : déclare le(s) widget(s) exposé(s).
@main
struct WelloWidgetBundle: WidgetBundle {
    var body: some Widget {
        WelloWidget()
    }
}
