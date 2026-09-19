import Foundation
import Testing
@testable import WelloKit

@Suite("TendanceMétéo")
struct TendanceMétéoTests {

    private func jour(_ offset: Int, _ tempC: Double) -> PrévisionJour {
        let date = Calendar.current.date(byAdding: .day, value: offset, to: .now) ?? .now
        return PrévisionJour(date: date, apparentTemperatureC: tempC)
    }

    @Test("premierJourChaud : liste vide → nil")
    func vide() {
        #expect(TendanceMétéo.premierJourChaud([]) == nil)
    }

    @Test("premierJourChaud : aucun jour au-dessus du seuil → nil")
    func aucunJourChaud() {
        let jours = [jour(1, 18), jour(2, 22), jour(3, 26)]
        #expect(TendanceMétéo.premierJourChaud(jours) == nil)
    }

    @Test("premierJourChaud : renvoie le premier jour au-dessus du seuil (pas le plus chaud)")
    func premierAuDessus() {
        let j1 = jour(1, 20)
        let j2 = jour(2, 34)   // plus chaud
        let j3 = jour(3, 29)   // aussi au-dessus, mais après j2
        #expect(TendanceMétéo.premierJourChaud([j1, j2, j3]) == j2)
    }

    @Test("premierJourChaud : exactement au seuil n'est pas retenu (strictement au-dessus)")
    func seuilExclusif() {
        let jours = [jour(1, 27)]   // = HydrationCalculator.Constantes.seuilConfortRessentiC
        #expect(TendanceMétéo.premierJourChaud(jours) == nil)
    }

    @Test("premierJourChaud : seuil personnalisé")
    func seuilPersonnalisé() {
        let jours = [jour(1, 24)]
        #expect(TendanceMétéo.premierJourChaud(jours, seuilC: 20) == jours[0])
        #expect(TendanceMétéo.premierJourChaud(jours, seuilC: 25) == nil)
    }
}
