import Testing
import Foundation
@testable import WelloKit

@Suite("WatchSync — codecs dictionnaire")
struct WatchSyncTests {

    @Test("PriseWatch : round-trip dictionnaire plist-safe")
    func priseRoundTrip() {
        let p = PriseWatch(id: UUID(), amountML: 250, loggedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let dict = p.dictionnaire()
        // Types plist-safe attendus (transportables par WCSession).
        #expect(dict["id"] is String)
        #expect(dict["amountML"] is Int)
        #expect(dict["loggedAt"] is Double)
        let décodé = PriseWatch(dictionnaire: dict)
        #expect(décodé == p)
    }

    @Test("PriseWatch : dictionnaire invalide → nil")
    func priseInvalide() {
        #expect(PriseWatch(dictionnaire: [:]) == nil)
        #expect(PriseWatch(dictionnaire: ["id": "pas-un-uuid", "amountML": 1, "loggedAt": 0.0]) == nil)
    }

    @Test("WatchSyncSnapshot : round-trip complet")
    func snapshotRoundTrip() {
        let s = WatchSyncSnapshot(
            objectifML: 2300, consomméML: 1200, quickAdds: [150, 250, 500], configuré: true,
            sexeRaw: "homme", etatPhysioRaw: nil, renalBonusML: 0,
            activitySensitivity: 1.0, weatherSensitivity: 1.0, manualAdjustmentML: 0,
            acquittés: [UUID(), UUID()], générémLe: Date(timeIntervalSince1970: 1_700_000_000))
        let décodé = WatchSyncSnapshot(dictionnaire: s.dictionnaire())
        #expect(décodé == s)
    }

    @Test("WatchSyncSnapshot : champs optionnels nil préservés")
    func snapshotOptionnels() {
        let s = WatchSyncSnapshot(
            objectifML: 0, consomméML: 0, quickAdds: [150, 250, 500], configuré: false,
            sexeRaw: nil, etatPhysioRaw: nil, renalBonusML: 0,
            activitySensitivity: 1.0, weatherSensitivity: 1.0, manualAdjustmentML: 0,
            acquittés: [], générémLe: Date(timeIntervalSince1970: 0))
        let décodé = WatchSyncSnapshot(dictionnaire: s.dictionnaire())
        #expect(décodé == s)
        #expect(décodé?.sexeRaw == nil)
        #expect(décodé?.acquittés.isEmpty == true)
    }

    @Test("WatchSyncSnapshot : dictionnaire incomplet → nil")
    func snapshotInvalide() {
        #expect(WatchSyncSnapshot(dictionnaire: ["objectifML": 2000]) == nil)
    }
}
