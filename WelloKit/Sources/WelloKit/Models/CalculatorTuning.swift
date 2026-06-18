/// Réglage avancé du calcul d'objectif (Wello+). Tous les défauts sont **neutres** : un tuning
/// `.neutre` reproduit exactement l'objectif standard. Les plafonds de sécurité du calculateur
/// (activité, météo, plafond global 4000 ml) restent appliqués quel que soit le réglage.
public struct CalculatorTuning: Sendable, Equatable {
    /// Sensibilité à l'effort : multiplie le bonus d'activité avant son plafond. 0,5–1,5.
    public let activityMultiplier: Double
    /// Sensibilité à la chaleur : multiplie le bonus météo avant son plafond. 0,5–1,5.
    public let weatherMultiplier: Double
    /// Ajustement manuel fixe (ml) ajouté/retiré à l'objectif. −500…+500.
    public let manualAdjustmentML: Int

    /// Réglage sans effet (objectif standard).
    public static let neutre = CalculatorTuning(activityMultiplier: 1, weatherMultiplier: 1,
                                                manualAdjustmentML: 0)

    /// Bornes exposées pour l'UI (steppers).
    public static let multiplierRange = 0.5...1.5
    public static let adjustmentLimit = 500

    /// Borne défensivement chaque valeur dans sa plage (saisie aberrante neutralisée).
    public init(activityMultiplier: Double, weatherMultiplier: Double, manualAdjustmentML: Int) {
        self.activityMultiplier = activityMultiplier.clamped(to: Self.multiplierRange)
        self.weatherMultiplier = weatherMultiplier.clamped(to: Self.multiplierRange)
        self.manualAdjustmentML = max(-Self.adjustmentLimit, min(Self.adjustmentLimit, manualAdjustmentML))
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
