/// Entrées du calcul d'objectif d'hydratation. `weather` est optionnel :
/// si la météo est indisponible (réseau/API down), le bonus météo vaut 0.
public struct CalculatorInputs: Sendable, Equatable {
    /// Sexe biologique : fixe la base EFSA (2000 ml homme / 1600 ml femme).
    public let sex: BiologicalSex
    /// Énergie active brûlée à l'effort aujourd'hui (kcal), issue de HealthKit.
    /// Proxy physiologique de la perte sudorale (intensité, pas seulement durée).
    public let activeEnergyKcal: Double
    public let weather: WeatherSnapshot?
    /// État physiologique (grossesse/allaitement) → terme additif EFSA.
    public let physiologicalState: PhysiologicalState
    /// Besoin rénal additif (lithiase). 0 si le suivi rénal est désactivé dans le profil.
    public let renalBonusML: Int
    /// Réglage avancé (Wello+). `.neutre` par défaut → objectif standard.
    public let tuning: CalculatorTuning

    public init(sex: BiologicalSex, activeEnergyKcal: Double, weather: WeatherSnapshot?,
                physiologicalState: PhysiologicalState = .aucun, renalBonusML: Int = 0,
                tuning: CalculatorTuning = .neutre) {
        self.sex = sex
        self.activeEnergyKcal = activeEnergyKcal
        self.weather = weather
        self.physiologicalState = physiologicalState
        self.renalBonusML = renalBonusML
        self.tuning = tuning
    }
}
