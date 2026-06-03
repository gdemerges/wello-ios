import Testing
@testable import WelloKit

@Suite("HydrationCalculator")
struct HydrationCalculatorTests {

    let calc = HydrationCalculator()

    @Test("Cas nominal : base = poids × 35, sans bonus")
    func casDeBase() {
        // 70 kg → 2450 ml de base ; aucun effort, pas de météo, plancher 2000.
        let inputs = CalculatorInputs(weightKg: 70, effortMinutes: 0, weather: nil, medicalFloorML: 2000)
        let r = calc.calculate(inputs)

        #expect(r.baseML == 2450)
        #expect(r.activityBonusML == 0)
        #expect(r.weatherBonusML == 0)
        #expect(r.totalML == 2450)
        #expect(r.plancherContraignant == false)
        #expect(r.plafondAppliqué == false)
    }

    @Test("Activité : 11 ml par minute d'effort")
    func activitéProportionnelle() {
        let inputs = CalculatorInputs(weightKg: 80, effortMinutes: 30, weather: nil, medicalFloorML: 2000)
        let r = calc.calculate(inputs)
        #expect(r.baseML == 2800)
        #expect(r.activityBonusML == 330)   // 30 × 11
        #expect(r.totalML == 3130)
    }

    @Test("Activité plafonnée à 1000 ml")
    func activitéPlafonnée() {
        // 120 min × 11 = 1320 → bridé à 1000.
        let inputs = CalculatorInputs(weightKg: 80, effortMinutes: 120, weather: nil, medicalFloorML: 2000)
        let r = calc.calculate(inputs)
        #expect(r.activityBonusML == 1000)
        #expect(r.totalML == 3800)           // 2800 + 1000
    }
}
