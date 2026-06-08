import Testing
import Foundation
@testable import WelloKit

@Suite("AdaptiveReminders")
struct AdaptiveRemindersTests {
    let planner = AdaptiveReminderPlanner()

    @Test("cold-start : moins de 7 jours de données → données insuffisantes")
    func coldStart() {
        let six = (0..<6).map { _ in JourDePrises(minutesDePrise: [480, 720]) }
        #expect(planner.aAssezDeDonnées(six) == false)
        let sept = (0..<7).map { _ in JourDePrises(minutesDePrise: [480, 720]) }
        #expect(planner.aAssezDeDonnées(sept) == true)
    }

    @Test("cold-start : un jour sans prise ne compte pas")
    func coldStartJoursVides() {
        var jours = (0..<7).map { _ in JourDePrises(minutesDePrise: [480]) }
        jours.append(JourDePrises(minutesDePrise: []))
        #expect(planner.aAssezDeDonnées(jours) == true)         // 7 jours pleins
        let presqueVide = (0..<6).map { _ in JourDePrises(minutesDePrise: [480]) }
            + [JourDePrises(minutesDePrise: [])]
        #expect(planner.aAssezDeDonnées(presqueVide) == false)  // 6 pleins seulement
    }

    @Test("fenêtre historique : percentiles des 1ʳᵉˢ/dernières prises")
    func fenêtreHistorique() {
        let jours = (0..<10).map { _ in JourDePrises(minutesDePrise: [480, 720, 1200]) }
        let f = planner.fenêtreDepuisHistorique(jours)
        #expect(f == FenêtreÉveil(réveilMin: 480, coucherMin: 1200))
    }

    @Test("fenêtre historique : aucune donnée → nil")
    func fenêtreHistoriqueVide() {
        #expect(planner.fenêtreDepuisHistorique([]) == nil)
        #expect(planner.fenêtreDepuisHistorique([JourDePrises(minutesDePrise: [])]) == nil)
    }

    @Test("fenêtre historique : bornes clampées")
    func fenêtreHistoriqueClamp() {
        // Réveil très tôt (2:00) et coucher très tard (23:50) → clampés.
        let jours = (0..<8).map { _ in JourDePrises(minutesDePrise: [120, 1430]) }
        let f = planner.fenêtreDepuisHistorique(jours)
        #expect(f?.réveilMin == 240)    // plancher 4:00
        #expect(f?.coucherMin == 1410)  // plafond 23:30
    }

    @Test("fenêtre sommeil : réveil = fin de sommeil, coucher = début")
    func fenêtreSommeil() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Paris")!
        func date(_ jour: Int, _ h: Int, _ m: Int) -> Date {
            cal.date(from: DateComponents(year: 2026, month: 6, day: jour, hour: h, minute: m))!
        }
        // 3 nuits : endormi 23:00 → réveil 07:00.
        let périodes = (1...3).map { j in
            PériodeSommeil(début: date(j, 23, 0), fin: date(j + 1, 7, 0))
        }
        let f = planner.fenêtreDepuisSommeil(périodes, calendar: cal)
        #expect(f == FenêtreÉveil(réveilMin: 420, coucherMin: 1380))
    }

    @Test("fenêtre sommeil : aucune période → nil")
    func fenêtreSommeilVide() {
        #expect(planner.fenêtreDepuisSommeil([], calendar: .current) == nil)
    }

    // Calendrier + fabrique de Date pour les tests de plan.
    private func calTest() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        return c
    }
    private func aujourdhui(_ cal: Calendar, _ h: Int, _ m: Int) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: h, minute: m))!
    }
    /// Minutes depuis minuit d'une Date produite par le plan (pour les assertions).
    private func minute(_ cal: Calendar, _ d: Date) -> Int {
        AdaptiveReminderPlanner.minuteDuJour(d, cal)
    }

    @Test("plan : trou récurrent l'après-midi → rappels préventifs")
    func planDétection() {
        let cal = calTest()
        let jours = (0..<10).map { _ in
            JourDePrises(minutesDePrise: [480, 630, 780, 930, 1080, 1230])
        }
        let plan = planner.planRappels(historique: jours, fenêtre: .défaut,
                                       now: aujourdhui(cal, 7, 0), objectifAtteint: false,
                                       calendar: cal)
        // Trous démarrant à 480/630/780/930/1080 → rappels = start + 120 − 15.
        #expect(plan.map { minute(cal, $0) } == [585, 735, 885, 1035, 1185])
    }

    @Test("plan : créneau non récurrent ignoré")
    func planNonRécurrent() {
        let cal = calTest()
        // 2 jours sur 10 ont un trou ; sous le seuil 40 % → aucun rappel.
        var jours = (0..<8).map { _ in JourDePrises(minutesDePrise: [480, 600, 720, 840, 960, 1080, 1200]) }
        jours += (0..<2).map { _ in JourDePrises(minutesDePrise: [480]) }
        let plan = planner.planRappels(historique: jours, fenêtre: .défaut,
                                       now: aujourdhui(cal, 7, 0), objectifAtteint: false,
                                       calendar: cal)
        #expect(plan.isEmpty)
    }

    @Test("plan : objectif atteint → aucun rappel")
    func planObjectifAtteint() {
        let cal = calTest()
        let jours = (0..<10).map { _ in JourDePrises(minutesDePrise: [480, 1230]) }
        let plan = planner.planRappels(historique: jours, fenêtre: .défaut,
                                       now: aujourdhui(cal, 7, 0), objectifAtteint: true,
                                       calendar: cal)
        #expect(plan.isEmpty)
    }

    @Test("plan : espacement < 90 min → le 2ᵉ créneau saute")
    func planEspacement() {
        let cal = calTest()
        // 5 jours : trou démarrant à 480 → rappel 585 (h9).
        // 5 jours : trou démarrant à 510 → rappel 615 (h10). 615−585 = 30 < 90.
        let a = (0..<5).map { _ in JourDePrises(minutesDePrise: [480]) }
        let b = (0..<5).map { _ in JourDePrises(minutesDePrise: [510]) }
        let plan = planner.planRappels(historique: a + b, fenêtre: .défaut,
                                       now: aujourdhui(cal, 7, 0), objectifAtteint: false,
                                       calendar: cal)
        #expect(plan.map { minute(cal, $0) } == [585])
    }

    @Test("plan : plafonné à 6 rappels/jour")
    func planPlafond() {
        let cal = calTest()
        let fenêtre = FenêtreÉveil(réveilMin: 300, coucherMin: 1320)
        let jours = (0..<10).map { _ in
            JourDePrises(minutesDePrise: [430, 560, 690, 820, 950, 1080, 1210])
        }
        let plan = planner.planRappels(historique: jours, fenêtre: fenêtre,
                                       now: aujourdhui(cal, 5, 0), objectifAtteint: false,
                                       calendar: cal)
        #expect(plan.count == 6)
    }

    @Test("plan : seuls les rappels futurs sont retournés")
    func planFutur() {
        let cal = calTest()
        let jours = (0..<10).map { _ in
            JourDePrises(minutesDePrise: [480, 630, 780, 930, 1080, 1230])
        }
        // now = 17:30 (1050) → seul 1185 (19:45) est futur.
        let plan = planner.planRappels(historique: jours, fenêtre: .défaut,
                                       now: aujourdhui(cal, 17, 30), objectifAtteint: false,
                                       calendar: cal)
        #expect(plan.map { minute(cal, $0) } == [1185])
    }
}
