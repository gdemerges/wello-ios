import Testing
@testable import WelloKit

@Suite("WidgetProgress")
struct WidgetProgressTests {

    @Test("Mi-parcours : fraction 0.5, 50 %")
    func miParcours() {
        let p = WidgetProgress(consomméML: 1150, objectifML: 2300)
        #expect(p.fraction == 0.5)
        #expect(p.pourcent == 50)
    }

    @Test("Objectif atteint : fraction bridée à 1.0, 100 %")
    func atteint() {
        let p = WidgetProgress(consomméML: 2300, objectifML: 2300)
        #expect(p.fraction == 1.0)
        #expect(p.pourcent == 100)
    }

    @Test("Dépassement : pourcent réel > 100, fraction bridée à 1.0")
    func dépassement() {
        let p = WidgetProgress(consomméML: 2500, objectifML: 2000)
        #expect(p.fraction == 1.0)
        #expect(p.pourcent == 125)
    }

    @Test("Consommé négatif (boisson diurétique) : clampé à 0 %")
    func négatif() {
        let p = WidgetProgress(consomméML: -50, objectifML: 2000)
        #expect(p.fraction == 0.0)
        #expect(p.pourcent == 0)
    }

    @Test("Objectif nul (non configuré) : 0 sans division par zéro")
    func objectifNul() {
        let p = WidgetProgress(consomméML: 500, objectifML: 0)
        #expect(p.fraction == 0.0)
        #expect(p.pourcent == 0)
    }

    @Test("Libellés en français : litres et pourcent")
    func libellés() {
        let p = WidgetProgress(consomméML: 1400, objectifML: 2300)
        #expect(p.consomméLitres == "1,4")
        #expect(p.objectifLitres == "2,3")
        #expect(p.libelléValeurs == "1,4 / 2,3 L")
        #expect(p.libelléPourcent == "61 %")
    }

    @Test("Formatage litres : un chiffre après la virgule, arrondi")
    func formatLitres() {
        #expect(WidgetProgress(consomméML: 500, objectifML: 2000).consomméLitres == "0,5")
        #expect(WidgetProgress(consomméML: 2000, objectifML: 2000).objectifLitres == "2,0")
        #expect(WidgetProgress(consomméML: 1950, objectifML: 2000).consomméLitres == "2,0")
    }
}
