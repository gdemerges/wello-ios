/// Calcul pur de l'objectif d'hydratation quotidien.
/// Aucune dépendance Apple framework : entièrement testable hors Xcode.
public struct HydrationCalculator: Sendable {

    /// Constantes médicales/algorithmiques nommées (cf. spec).
    public enum Constantes {
        /// Cible de boisson EFSA 2010 (eau totale 2,5 L / 2,0 L, dont ~80 % via les boissons).
        public static let baseHommeML = 2000
        public static let baseFemmeML = 1600
        /// ml d'eau par kcal d'énergie active. Base scientifique : évaporer 1 mL de sueur
        /// dissipe ~0,58 kcal ; à l'effort ~75-80 % de l'énergie devient chaleur, dissipée
        /// majoritairement par la sueur → ~1 mL/kcal (coefficient conservateur).
        public static let mlParKcal = 1.0
        public static let plafondActivité = 1000
        /// Température ressentie (°C) en dessous de laquelle aucun bonus météo (zone de confort).
        public static let seuilConfortRessentiC = 27.0
        /// ml d'eau supplémentaires par °C ressenti au-dessus du seuil de confort.
        public static let mlParDegréRessenti = 50.0
        /// Plafond du bonus météo (≈ +12°C ressentis au-dessus du confort).
        public static let plafondMétéo = 600
        /// Plafond de sécurité global : on n'affiche jamais d'objectif supérieur.
        public static let plafondGlobal = 4000
    }

    public init() {}

    public func calculate(_ inputs: CalculatorInputs) -> GoalBreakdown {
        let t = inputs.tuning
        let base = inputs.sex == .homme ? Constantes.baseHommeML : Constantes.baseFemmeML

        // Réglage avancé : la sensibilité multiplie le bonus AVANT son plafond de sécurité.
        let activité = min(Int((inputs.activeEnergyKcal * Constantes.mlParKcal * t.activityMultiplier).rounded()),
                           Constantes.plafondActivité)

        let météo = bonusMétéo(inputs.weather, multiplicateur: t.weatherMultiplier)

        let étatPhysio = inputs.physiologicalState.bonusML
        // Garde-fou : un besoin rénal négatif (saisie aberrante) ne retire jamais d'eau.
        let rénal = max(0, inputs.renalBonusML)

        // Ajustement manuel (peut être négatif) ; le total est borné ≥ 0 puis au plafond.
        let physiologique = max(0, base + activité + météo + étatPhysio + rénal + t.manualAdjustmentML)
        // Plafond de sécurité anti-hyperhydratation : unique garde-fou (plus de plancher).
        let total = min(Constantes.plafondGlobal, physiologique)

        return GoalBreakdown(
            baseML: base,
            activityBonusML: activité,
            weatherBonusML: météo,
            lifeStageBonusML: étatPhysio,
            renalBonusML: rénal,
            manualAdjustmentML: t.manualAdjustmentML,
            totalML: total,
            plafondAppliqué: physiologique > Constantes.plafondGlobal
        )
    }

    private func bonusMétéo(_ weather: WeatherSnapshot?, multiplicateur: Double) -> Int {
        guard let w = weather else { return 0 }   // météo absente → bonus 0
        // Montée linéaire à partir du seuil de confort, plafonnée. La température ressentie
        // combine déjà chaleur + humidité + vent (cf. WeatherSnapshot).
        let excès = w.apparentTemperatureC - Constantes.seuilConfortRessentiC
        guard excès > 0 else { return 0 }
        return min(Int((excès * Constantes.mlParDegréRessenti * multiplicateur).rounded()), Constantes.plafondMétéo)
    }
}
