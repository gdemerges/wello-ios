import Testing
@testable import WelloKit

@Suite("CalculatorTuning")
struct CalculatorTuningTests {
    let calc = HydrationCalculator()

    @Test("Tuning neutre = objectif standard (non-régression)")
    func neutre() {
        let standard = calc.calculate(CalculatorInputs(sex: .homme, activeEnergyKcal: 300, weather: nil))
        let neutre = calc.calculate(CalculatorInputs(sex: .homme, activeEnergyKcal: 300, weather: nil,
                                                     tuning: .neutre))
        #expect(standard == neutre)
    }

    @Test("Sensibilité effort multiplie le bonus d'activité avant plafond")
    func sensibilitéEffort() {
        // 300 kcal × 1 mL/kcal = 300 ; ×1,5 = 450.
        let t = CalculatorTuning(activityMultiplier: 1.5, weatherMultiplier: 1, manualAdjustmentML: 0)
        let r = calc.calculate(CalculatorInputs(sex: .homme, activeEnergyKcal: 300, weather: nil, tuning: t))
        #expect(r.activityBonusML == 450)
        #expect(r.totalML == 2000 + 450)
    }

    @Test("Sensibilité effort : le plafond d'activité (1000) reste appliqué")
    func sensibilitéEffortPlafonnée() {
        // 800 kcal ×1,5 = 1200 → plafonné à 1000.
        let t = CalculatorTuning(activityMultiplier: 1.5, weatherMultiplier: 1, manualAdjustmentML: 0)
        let r = calc.calculate(CalculatorInputs(sex: .homme, activeEnergyKcal: 800, weather: nil, tuning: t))
        #expect(r.activityBonusML == 1000)
    }

    @Test("Sensibilité chaleur multiplie le bonus météo")
    func sensibilitéChaleur() {
        // ressenti 33 → excès 6°C ×50 = 300 ; ×0,5 = 150.
        let t = CalculatorTuning(activityMultiplier: 1, weatherMultiplier: 0.5, manualAdjustmentML: 0)
        let r = calc.calculate(CalculatorInputs(sex: .homme, activeEnergyKcal: 0,
                                                weather: WeatherSnapshot(apparentTemperatureC: 33), tuning: t))
        #expect(r.weatherBonusML == 150)
    }

    @Test("Ajustement manuel positif s'ajoute au total et apparaît dans le breakdown")
    func ajustementPositif() {
        let t = CalculatorTuning(activityMultiplier: 1, weatherMultiplier: 1, manualAdjustmentML: 300)
        let r = calc.calculate(CalculatorInputs(sex: .homme, activeEnergyKcal: 0, weather: nil, tuning: t))
        #expect(r.manualAdjustmentML == 300)
        #expect(r.totalML == 2000 + 300)
    }

    @Test("Ajustement manuel négatif retire de l'eau, total jamais < 0")
    func ajustementNégatif() {
        let t = CalculatorTuning(activityMultiplier: 1, weatherMultiplier: 1, manualAdjustmentML: -500)
        let r = calc.calculate(CalculatorInputs(sex: .femme, activeEnergyKcal: 0, weather: nil, tuning: t))
        #expect(r.totalML == 1600 - 500)
    }

    @Test("Le plafond global 4000 reste appliqué malgré un ajustement positif")
    func plafondGlobalRespecté() {
        let t = CalculatorTuning(activityMultiplier: 1, weatherMultiplier: 1, manualAdjustmentML: 500)
        // base 2000 + activité plafonnée 1000 + météo plafonnée 600 + manuel 500 = 4100 → 4000.
        let r = calc.calculate(CalculatorInputs(sex: .homme, activeEnergyKcal: 2000,
                                                weather: WeatherSnapshot(apparentTemperatureC: 50), tuning: t))
        #expect(r.totalML == 4000)
        #expect(r.plafondAppliqué)
    }

    @Test("Valeurs hors plage bornées à l'init (saisie aberrante neutralisée)")
    func bornage() {
        let t = CalculatorTuning(activityMultiplier: 9, weatherMultiplier: -3, manualAdjustmentML: 99999)
        #expect(t.activityMultiplier == 1.5)
        #expect(t.weatherMultiplier == 0.5)
        #expect(t.manualAdjustmentML == 500)
    }
}
