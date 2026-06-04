import Testing
import Foundation
@testable import WelloKit

@Suite("Premium")
struct PremiumTests {

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    @Test("free ne déverrouille aucune feature premium")
    func freeVerrouille() {
        let e = Entitlements(status: .free)
        for f in PremiumFeature.allCases {
            #expect(e.isUnlocked(f) == false)
        }
    }

    @Test("plus déverrouille toutes les features")
    func plusDéverrouille() {
        let e = Entitlements(status: .plus)
        for f in PremiumFeature.allCases {
            #expect(e.isUnlocked(f) == true)
        }
    }

    @Test("historyVisibleSince : plus = illimité (nil)")
    func historiquePlus() {
        #expect(historyVisibleSince(status: .plus, now: .now, calendar: utc) == nil)
    }

    @Test("historyVisibleSince : free = début du jour 6 jours avant aujourd'hui (7 jours inclus)")
    func historiqueFree() {
        let now = utc.date(from: DateComponents(year: 2026, month: 6, day: 4, hour: 15, minute: 30))!
        let attendu = utc.date(from: DateComponents(year: 2026, month: 5, day: 29, hour: 0, minute: 0))!
        #expect(historyVisibleSince(status: .free, now: now, calendar: utc) == attendu)
    }
}
