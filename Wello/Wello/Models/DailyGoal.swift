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
    /// Terme additif état physiologique (grossesse/allaitement). Défaut inline (migration légère).
    var lifeStageBonusML: Int = 0
    /// Terme additif besoin rénal (0 si désactivé). Défaut inline (migration légère).
    var renalBonusML: Int = 0
    /// Terme additif du réglage avancé (ajustement manuel, peut être négatif). Défaut inline.
    var manualAdjustmentML: Int = 0
    var totalML: Int
    var calculatedAt: Date

    init(date: Date, baseML: Int, activityBonusML: Int, weatherBonusML: Int,
         lifeStageBonusML: Int = 0, renalBonusML: Int = 0, manualAdjustmentML: Int = 0,
         totalML: Int, calculatedAt: Date = .now) {
        self.date = date
        self.baseML = baseML
        self.activityBonusML = activityBonusML
        self.weatherBonusML = weatherBonusML
        self.lifeStageBonusML = lifeStageBonusML
        self.renalBonusML = renalBonusML
        self.manualAdjustmentML = manualAdjustmentML
        self.totalML = totalML
        self.calculatedAt = calculatedAt
    }
}
