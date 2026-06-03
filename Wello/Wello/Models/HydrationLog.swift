import Foundation
import SwiftData

/// Une prise d'eau enregistrée.
@Model
final class HydrationLog {
    var amountML: Int
    var loggedAt: Date
    /// Provenance : "app" (saisie dans Wello) ou "healthkit" (importée).
    var source: String
    /// UUID de l'échantillon HealthKit d'origine, pour les prises importées (dédup).
    /// nil pour les prises saisies dans Wello.
    var healthKitUUID: UUID?

    init(amountML: Int, loggedAt: Date = .now, source: String = "app",
         healthKitUUID: UUID? = nil) {
        self.amountML = amountML
        self.loggedAt = loggedAt
        self.source = source
        self.healthKitUUID = healthKitUUID
    }
}
