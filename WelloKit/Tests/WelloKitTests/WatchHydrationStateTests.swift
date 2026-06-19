import Testing
import Foundation
@testable import WelloKit

@Suite("ÉtatHydratationWatch")
struct WatchHydrationStateTests {

    private func snapshot(objectif: Int = 2300, consommé: Int = 1000, acquittés: [UUID] = [],
                          sexe: String? = "homme") -> WatchSyncSnapshot {
        WatchSyncSnapshot(
            objectifML: objectif, consomméML: consommé, quickAdds: [150, 250, 500], configuré: sexe != nil,
            sexeRaw: sexe, etatPhysioRaw: nil, renalBonusML: 0,
            activitySensitivity: 1.0, weatherSensitivity: 1.0, manualAdjustmentML: 0,
            acquittés: acquittés, générémLe: .init(timeIntervalSince1970: 1_700_000_000))
    }

    @Test("Sans snapshot : non configuré, consommé 0, objectif 0")
    func vide() {
        let é = ÉtatHydratationWatch()
        #expect(é.configuré == false)
        #expect(é.consomméML == 0)
        #expect(é.objectifML == 0)
    }

    @Test("Consommé = autoritaire + prises non acquittées")
    func consomméOptimiste() {
        var é = ÉtatHydratationWatch()
        é.appliquer(snapshot(consommé: 1000))
        é.ajouterPrise(PriseWatch(amountML: 250))
        é.ajouterPrise(PriseWatch(amountML: 150))
        #expect(é.consomméML == 1400)   // 1000 + 250 + 150
    }

    @Test("Application d'un snapshot : purge les prises acquittées")
    func purgeAcquittées() {
        var é = ÉtatHydratationWatch()
        let p = PriseWatch(amountML: 250)
        é.appliquer(snapshot(consommé: 1000))
        é.ajouterPrise(p)
        #expect(é.consomméML == 1250)
        // L'iPhone a absorbé p (consommé autoritaire monte à 1250, p acquittée) → plus de double compte.
        é.appliquer(snapshot(consommé: 1250, acquittés: [p.id]))
        #expect(é.consomméML == 1250)
        #expect(é.prisesEnAttente.isEmpty)
    }

    @Test("Hors-ligne : les prises s'empilent sur le dernier consommé connu")
    func horsLigne() {
        var é = ÉtatHydratationWatch()
        é.appliquer(snapshot(consommé: 800))
        é.ajouterPrise(PriseWatch(amountML: 250))
        é.ajouterPrise(PriseWatch(amountML: 250))
        #expect(é.consomméML == 1300)   // aucun acquittement reçu
    }

    @Test("Objectif = max(poussé, recalculé depuis énergie active)")
    func recalculObjectif() {
        var é = ÉtatHydratationWatch()
        é.appliquer(snapshot(objectif: 2000, sexe: "homme"))   // base homme 2000, sans activité
        é.mettreÀJourÉnergie(600)                              // +600 ml d'activité (1 ml/kcal)
        #expect(é.objectifML == 2600)                          // max(2000, 2000+600)
    }

    @Test("Objectif : le poussé gagne s'il est supérieur (météo connue de l'iPhone)")
    func pousséGagne() {
        var é = ÉtatHydratationWatch()
        é.appliquer(snapshot(objectif: 2900, sexe: "homme"))   // inclut un bonus météo
        é.mettreÀJourÉnergie(100)                              // recalcul local 2100 < 2900
        #expect(é.objectifML == 2900)
    }

    @Test("Configuré sans sexe : pas de recalcul possible, on garde le poussé")
    func sexeInconnu() {
        // Snapshot configuré (objectif poussé valide) mais sans sexeRaw → recalcul impossible.
        let s = WatchSyncSnapshot(
            objectifML: 1800, consomméML: 0, quickAdds: [150, 250, 500], configuré: true,
            sexeRaw: nil, etatPhysioRaw: nil, renalBonusML: 0,
            activitySensitivity: 1.0, weatherSensitivity: 1.0, manualAdjustmentML: 0,
            acquittés: [], générémLe: .init(timeIntervalSince1970: 0))
        var é = ÉtatHydratationWatch()
        é.appliquer(s)
        é.mettreÀJourÉnergie(500)
        #expect(é.objectifML == 1800)
    }

    @Test("Annuler la dernière prise en attente")
    func annuler() {
        var é = ÉtatHydratationWatch()
        é.appliquer(snapshot(consommé: 1000))
        é.ajouterPrise(PriseWatch(amountML: 250))
        let p2 = PriseWatch(amountML: 150)
        é.ajouterPrise(p2)
        let retirée = é.annulerDernièreEnAttente()
        #expect(retirée == p2)
        #expect(é.consomméML == 1250)
    }

    @Test("progress reflète consommé/objectif via WidgetProgress")
    func progress() {
        var é = ÉtatHydratationWatch()
        é.appliquer(snapshot(objectif: 2000, consommé: 1000))
        #expect(é.progress.fraction == 0.5)
        #expect(é.progress.pourcent == 50)
    }
}
