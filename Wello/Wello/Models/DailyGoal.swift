import Foundation
import SwiftData

/// Objectif calculé pour un jour donné (un seul par date, normalisée à minuit).
@Model
final class DailyGoal {
    /// Date du jour, normalisée au début de journée (`startOfDay`).
    @Attribute(.unique) var date: Date
    var baseML: Int
    var activityBonusML: Int
    var weatherBonusML: Int
    /// Terme additif altitude (0 en plaine / indisponible). Défaut inline (migration légère).
    var altitudeBonusML: Int = 0
    /// Terme additif état physiologique (grossesse/allaitement). Défaut inline (migration légère).
    var lifeStageBonusML: Int = 0
    /// Terme additif besoin rénal (0 si désactivé). Défaut inline (migration légère).
    var renalBonusML: Int = 0
    /// Ajustement de corpulence (Wello+, peut être négatif ; 0 si non personnalisé). Défaut inline.
    var bodyBonusML: Int = 0
    /// Terme additif du réglage avancé (ajustement manuel, peut être négatif). Défaut inline.
    var manualAdjustmentML: Int = 0
    var totalML: Int
    /// Consommé effectif du jour (ml), dénormalisé depuis les `HydrationLog`. Défaut inline
    /// (migration légère). Écrit par `HydrationStore` à chaque mutation des prises du jour :
    /// l'historique et les analyses lisent cette colonne au lieu de réagréger tout l'historique
    /// des prises à chaque rendu. Toujours borné à ≥ 0 (`clampedDayTotal`).
    var consumedML: Int = 0
    var calculatedAt: Date

    init(date: Date, baseML: Int, activityBonusML: Int, weatherBonusML: Int,
         altitudeBonusML: Int = 0, lifeStageBonusML: Int = 0, renalBonusML: Int = 0,
         bodyBonusML: Int = 0, manualAdjustmentML: Int = 0,
         totalML: Int, consumedML: Int = 0, calculatedAt: Date = .now) {
        self.date = date
        self.baseML = baseML
        self.activityBonusML = activityBonusML
        self.weatherBonusML = weatherBonusML
        self.altitudeBonusML = altitudeBonusML
        self.lifeStageBonusML = lifeStageBonusML
        self.renalBonusML = renalBonusML
        self.bodyBonusML = bodyBonusML
        self.manualAdjustmentML = manualAdjustmentML
        self.totalML = totalML
        self.consumedML = consumedML
        self.calculatedAt = calculatedAt
    }
}
