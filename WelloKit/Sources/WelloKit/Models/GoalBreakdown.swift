/// Résultat détaillé du calcul, pour affichage du breakdown dans l'UI.
/// Modèle 100 % additif : le total est la somme des termes, bridée au plafond de sécurité.
public struct GoalBreakdown: Sendable, Equatable {
    public let baseML: Int
    public let activityBonusML: Int
    public let weatherBonusML: Int
    /// Terme additif lié à l'état physiologique (grossesse +300 / allaitement +700 / aucun 0).
    public let lifeStageBonusML: Int
    /// Terme additif lié au besoin rénal (lithiase). 0 si désactivé. Toujours ≥ 0 :
    /// `HydrationCalculator.calculate` applique `max(0, …)` avant de construire le breakdown.
    public let renalBonusML: Int
    /// Terme additif du réglage avancé (ajustement manuel, Wello+). Peut être négatif. 0 par défaut.
    public let manualAdjustmentML: Int
    public let totalML: Int
    /// Vrai si l'objectif a été bridé au plafond de sécurité (anti-hyperhydratation).
    public let plafondAppliqué: Bool

    /// Besoin physiologique = somme de tous les termes additifs (= total avant plafond, borné ≥ 0).
    public var physiologicalML: Int {
        max(0, baseML + activityBonusML + weatherBonusML + lifeStageBonusML + renalBonusML + manualAdjustmentML)
    }

    public init(baseML: Int, activityBonusML: Int, weatherBonusML: Int, lifeStageBonusML: Int,
                renalBonusML: Int, manualAdjustmentML: Int = 0, totalML: Int, plafondAppliqué: Bool) {
        self.baseML = baseML
        self.activityBonusML = activityBonusML
        self.weatherBonusML = weatherBonusML
        self.lifeStageBonusML = lifeStageBonusML
        self.renalBonusML = renalBonusML
        self.manualAdjustmentML = manualAdjustmentML
        self.totalML = totalML
        self.plafondAppliqué = plafondAppliqué
    }
}
