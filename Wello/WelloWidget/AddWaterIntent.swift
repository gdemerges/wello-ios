import AppIntents
import SwiftData
import WidgetKit
import WelloKit

/// Ajoute une prise d'eau directement depuis le widget moyen, sans ouvrir l'app.
/// Insère un `HydrationLog` (eau, coefficient 1.0) dans le store partagé puis recharge les widgets.
struct AddWaterIntent: AppIntent {
    static var title: LocalizedStringResource = "Ajouter de l'eau"

    @Parameter(title: "Quantité (ml)")
    var amountML: Int

    init() {}
    init(amountML: Int) { self.amountML = amountML }

    func perform() async throws -> some IntentResult {
        let container = WelloShared.makeModelContainer()
        let ctx = ModelContext(container)
        ctx.insert(HydrationLog(amountML: amountML, source: "app",
                                drinkType: "water", coefficient: 1.0))
        try ctx.save()
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
