import AppIntents
import SwiftData
import WidgetKit
import WelloKit

/// Ajoute une prise d'eau sans ouvrir l'app. Intent **partagé** (dossier `App/`, membre des cibles
/// app ET widget) : utilisé par le widget moyen (boutons +150/+250/+500), le Control Widget iOS 18,
/// et les App Shortcuts (Siri / Spotlight / Bouton Action) déclarés dans `WaterAppShortcuts`.
/// Écrit un `HydrationLog` (eau, coefficient 1.0) dans le store partagé (App Group) puis recharge
/// les widgets. Ne s'ouvre jamais : logging silencieux, avec un retour vocal/visuel pour Siri.
struct AddWaterIntent: AppIntent {
    static var title: LocalizedStringResource = "Ajouter de l'eau"
    static var description = IntentDescription("Enregistre une prise d'eau dans Wello.")
    /// Logging en tâche de fond : ni le Bouton Action ni Siri n'ouvrent l'app.
    static var openAppWhenRun = false

    @Parameter(title: "Quantité (ml)", default: 250)
    var amountML: Int

    init() {}
    init(amountML: Int) { self.amountML = amountML }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let ctx = ModelContext(WelloShared.partagé)
        ctx.insert(HydrationLog(amountML: amountML, source: "app",
                                drinkType: "water", coefficient: 1.0))
        try ctx.save()
        WidgetCenter.shared.reloadAllTimelines()

        // Total du jour → retour utile pour Siri (« 250 ml ajoutés, tu en es à 1,2 L »).
        let début = Calendar.current.startOfDay(for: .now)
        let descripteur = FetchDescriptor<HydrationLog>(
            predicate: #Predicate { $0.loggedAt >= début }
        )
        let total = clampedDayTotal((try? ctx.fetch(descripteur))?.reduce(0) { $0 + $1.effectiveML } ?? amountML)

        // Le `DailyGoal` du jour porte son consommé (colonne dénormalisée que lisent l'historique
        // et les analyses) : cet intent écrit hors de l'app, c'est à lui de la maintenir — sinon
        // l'historique afficherait un « bu » d'avant la prise jusqu'au prochain recalcul complet.
        let jour = FetchDescriptor<DailyGoal>(predicate: #Predicate { $0.date == début })
        if let goal = try? ctx.fetch(jour).first, goal.consumedML != total {
            goal.consumedML = total
            try? ctx.save()
        }

        let litres = Double(total) / 1000
        return .result(dialog: "\(amountML) ml ajoutés — tu en es à \(litres.formatted(.number.precision(.fractionLength(1)))) L aujourd'hui. 💧")
    }
}
