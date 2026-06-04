import Testing
@testable import WelloKit

@Suite("HydrationStats")
struct HydrationStatsTests {

    private func jour(_ bu: Int, _ obj: Int) -> DailyTotal { DailyTotal(consumedML: bu, goalML: obj) }

    @Test("Série : jours atteints consécutifs depuis le plus récent")
    func sérieNominale() {
        // récent → ancien : atteint, atteint, raté, atteint
        let days = [jour(2600, 2500), jour(2500, 2500), jour(1000, 2500), jour(3000, 2500)]
        #expect(HydrationStats.currentStreak(days) == 2)
    }

    @Test("Série : tous atteints")
    func sérieComplète() {
        let days = [jour(2600, 2500), jour(2700, 2500), jour(2500, 2500)]
        #expect(HydrationStats.currentStreak(days) == 3)
    }

    @Test("Série : le jour le plus récent raté → 0")
    func sérieRompue() {
        let days = [jour(1000, 2500), jour(2600, 2500)]
        #expect(HydrationStats.currentStreak(days) == 0)
    }

    @Test("Série : liste vide → 0")
    func sérieVide() {
        #expect(HydrationStats.currentStreak([]) == 0)
    }

    @Test("Moyenne sur les N derniers jours")
    func moyenne() {
        let days = [jour(3000, 2500), jour(2000, 2500), jour(1000, 2500), jour(4000, 2500)]
        #expect(HydrationStats.averageConsumed(days, lastN: 3) == 2000)   // (3000+2000+1000)/3
        #expect(HydrationStats.averageConsumed(days, lastN: 10) == 2500)  // (3000+2000+1000+4000)/4
        #expect(HydrationStats.averageConsumed([], lastN: 7) == 0)
    }

    @Test("reachRate : liste vide → 0")
    func tauxVide() {
        #expect(HydrationStats.reachRate([]) == 0)
    }

    @Test("reachRate : 3 jours atteints sur 4 → 0.75")
    func tauxPartiel() {
        let days = [jour(2600, 2500), jour(1000, 2500), jour(2500, 2500), jour(3000, 2500)]
        #expect(HydrationStats.reachRate(days) == 0.75)
    }

    @Test("reachRate : tous atteints → 1.0")
    func tauxComplet() {
        let days = [jour(2600, 2500), jour(2700, 2500)]
        #expect(HydrationStats.reachRate(days) == 1.0)
    }

    @Test("bestStreak : liste vide → 0")
    func recordVide() {
        #expect(HydrationStats.bestStreak([]) == 0)
    }

    @Test("bestStreak : record au milieu d'une séquence")
    func recordMilieu() {
        // ✓ ✗ ✓ ✓ ✓ ✗ ✓  → record = 3
        let days = [jour(2600, 2500), jour(1000, 2500), jour(2600, 2500), jour(2600, 2500),
                    jour(2600, 2500), jour(1000, 2500), jour(2600, 2500)]
        #expect(HydrationStats.bestStreak(days) == 3)
    }

    @Test("bestStreak : tous atteints → n")
    func recordComplet() {
        let days = [jour(2600, 2500), jour(2700, 2500), jour(2800, 2500)]
        #expect(HydrationStats.bestStreak(days) == 3)
    }

    @Test("DayPeriod.from : bornes des tranches")
    func tranchesHoraires() {
        #expect(DayPeriod.from(hour: 0) == .nuit)
        #expect(DayPeriod.from(hour: 5) == .nuit)
        #expect(DayPeriod.from(hour: 6) == .matin)
        #expect(DayPeriod.from(hour: 10) == .matin)
        #expect(DayPeriod.from(hour: 11) == .midi)
        #expect(DayPeriod.from(hour: 13) == .midi)
        #expect(DayPeriod.from(hour: 14) == .apresMidi)
        #expect(DayPeriod.from(hour: 17) == .apresMidi)
        #expect(DayPeriod.from(hour: 18) == .soiree)
        #expect(DayPeriod.from(hour: 22) == .soiree)
        #expect(DayPeriod.from(hour: 23) == .nuit)
    }

    @Test("hydrationByPeriod : renvoie toujours 5 tranches dans l'ordre canonique")
    func répartitionOrdre() {
        let r = HydrationStats.hydrationByPeriod([])
        #expect(r.map(\.period) == [.matin, .midi, .apresMidi, .soiree, .nuit])
        #expect(r.allSatisfy { $0.ml == 0 })
    }

    @Test("hydrationByPeriod : agrège les ml par tranche")
    func répartitionSomme() {
        let entries: [(hour: Int, ml: Int)] = [
            (8, 250), (9, 250),   // matin = 500
            (13, 300),            // midi = 300
            (20, 500),            // soirée = 500
        ]
        let r = HydrationStats.hydrationByPeriod(entries)
        let parTranche = Dictionary(uniqueKeysWithValues: r.map { ($0.period, $0.ml) })
        #expect(parTranche[.matin] == 500)
        #expect(parTranche[.midi] == 300)
        #expect(parTranche[.apresMidi] == 0)
        #expect(parTranche[.soiree] == 500)
        #expect(parTranche[.nuit] == 0)
    }
}
