import Foundation
import SwiftData
import WelloKit

/// Une prise enregistrée (eau ou autre boisson).
@Model
final class HydrationLog {
    var amountML: Int
    var loggedAt: Date
    /// Provenance : "app" (saisie dans Wello) ou "healthkit" (importée).
    var source: String
    /// UUID de l'échantillon HealthKit d'origine, pour les prises importées (dédup).
    /// nil pour les prises saisies dans Wello.
    var healthKitUUID: UUID?
    /// Type de boisson (rawValue `DrinkType`). Défaut inline = migration légère SwiftData ;
    /// "water" pour les prises existantes et les imports HealthKit.
    var drinkType: String = "water"
    /// Coefficient d'hydratation snapshoté au moment de la prise. N'est jamais réécrit ensuite
    /// (éditer un coefficient au Profil ne modifie pas l'historique).
    var coefficient: Double = 1.0

    /// Boisson typée (repli sur l'eau si la valeur stockée est inconnue).
    var drink: DrinkType { DrinkType(rawValue: drinkType) ?? .water }

    /// Hydratation effective (ml) : `volume × coefficient`, arrondi. Peut être négatif.
    var effectiveML: Int { effectiveHydrationML(volumeML: amountML, coefficient: coefficient) }

    init(amountML: Int, loggedAt: Date = .now, source: String = "app",
         healthKitUUID: UUID? = nil,
         drinkType: String = "water", coefficient: Double = 1.0) {
        self.amountML = amountML
        self.loggedAt = loggedAt
        self.source = source
        self.healthKitUUID = healthKitUUID
        self.drinkType = drinkType
        self.coefficient = coefficient
    }
}
