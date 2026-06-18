import Testing
import Foundation
@testable import WelloKit

@Suite("HydrationExport")
struct HydrationExportTests {

    private let gmt = TimeZone(identifier: "GMT")!

    /// 2026-06-18T14:30:00 GMT
    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0, _ s: Int = 0) -> Date {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi; c.second = s
        c.timeZone = gmt
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    @Test("Détail : en-tête + lignes, horodatage local et coefficient point")
    func détail() {
        let rows = [
            ExportLogRow(loggedAt: date(2026, 6, 18, 14, 30, 0), drinkLabel: "Eau",
                         volumeML: 250, coefficient: 1.0, effectiveML: 250, source: "app"),
            ExportLogRow(loggedAt: date(2026, 6, 18, 9, 5, 0), drinkLabel: "Café",
                         volumeML: 100, coefficient: 0.8, effectiveML: 80, source: "app"),
        ]
        let csv = HydrationExport.detailCSV(rows, timeZone: gmt)
        let lignes = csv.components(separatedBy: "\r\n")
        #expect(lignes.count == 3)
        #expect(lignes[0] == "Horodatage,Boisson,Volume (ml),Coefficient,Effectif (ml),Source")
        #expect(lignes[1] == "2026-06-18T14:30:00,Eau,250,1.00,250,app")
        #expect(lignes[2] == "2026-06-18T09:05:00,Café,100,0.80,80,app")
    }

    @Test("Résumé : atteint oui/non selon objectif")
    func résumé() {
        let days = [
            ExportDaySummary(day: date(2026, 6, 18), consumedML: 2100, goalML: 2000),
            ExportDaySummary(day: date(2026, 6, 17), consumedML: 1500, goalML: 2000),
        ]
        let csv = HydrationExport.summaryCSV(days, timeZone: gmt)
        let lignes = csv.components(separatedBy: "\r\n")
        #expect(lignes[0] == "Jour,Consommé (ml),Objectif (ml),Atteint")
        #expect(lignes[1] == "2026-06-18,2100,2000,oui")
        #expect(lignes[2] == "2026-06-17,1500,2000,non")
    }

    @Test("Objectif nul → jamais atteint (pas de division par zéro)")
    func objectifNul() {
        let csv = HydrationExport.summaryCSV(
            [ExportDaySummary(day: date(2026, 6, 18), consumedML: 0, goalML: 0)], timeZone: gmt)
        #expect(csv.hasSuffix("2026-06-18,0,0,non"))
    }

    @Test("Échappement RFC 4180 : virgule et guillemets dans un libellé")
    func échappement() {
        let rows = [ExportLogRow(loggedAt: date(2026, 6, 18, 8, 0, 0),
                                 drinkLabel: "Thé \"vert\", menthe",
                                 volumeML: 200, coefficient: 1.0, effectiveML: 200, source: "app")]
        let csv = HydrationExport.detailCSV(rows, timeZone: gmt)
        // Le champ est entouré de guillemets et les guillemets internes doublés.
        #expect(csv.contains("\"Thé \"\"vert\"\", menthe\""))
    }

    @Test("Listes vides → en-tête seul")
    func vide() {
        #expect(HydrationExport.detailCSV([], timeZone: gmt)
                == "Horodatage,Boisson,Volume (ml),Coefficient,Effectif (ml),Source")
        #expect(HydrationExport.summaryCSV([], timeZone: gmt)
                == "Jour,Consommé (ml),Objectif (ml),Atteint")
    }
}
