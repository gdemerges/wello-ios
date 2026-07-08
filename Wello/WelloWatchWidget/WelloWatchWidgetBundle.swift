import WidgetKit
import SwiftUI

/// Point d'entrée de l'extension complication watchOS : déclare la complication de cadran.
@main
struct WelloWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        WelloComplication()
    }
}
