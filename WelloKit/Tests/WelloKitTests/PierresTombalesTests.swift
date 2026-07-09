import Testing
import Foundation
@testable import WelloKit

@Suite("PierresTombales")
struct PierresTombalesTests {
    let ttl: TimeInterval = 2 * 86400
    let maintenant = Date(timeIntervalSince1970: 1_000_000)
    let u1 = UUID(), u2 = UUID()

    @Test("valides garde le récent, écarte l'expiré")
    func valides() {
        let raw = [
            u1.uuidString: maintenant.timeIntervalSince1970 - 3600,          // il y a 1 h → valide
            u2.uuidString: maintenant.timeIntervalSince1970 - 3 * 86400      // il y a 3 j → expiré
        ]
        let set = PierresTombales.valides(raw, maintenant: maintenant, ttl: ttl)
        #expect(set == [u1])
    }

    @Test("valides ignore les clés non-UUID")
    func clésInvalides() {
        let raw = ["pas-un-uuid": maintenant.timeIntervalSince1970]
        #expect(PierresTombales.valides(raw, maintenant: maintenant, ttl: ttl).isEmpty)
    }

    @Test("enAjoutant purge l'expiré et ajoute le nouvel UUID")
    func enAjoutant() {
        let raw = [u2.uuidString: maintenant.timeIntervalSince1970 - 3 * 86400]  // expiré
        let out = PierresTombales.enAjoutant(u1, à: raw, maintenant: maintenant, ttl: ttl)
        #expect(out[u1.uuidString] == maintenant.timeIntervalSince1970)
        #expect(out[u2.uuidString] == nil)   // purgé
        #expect(PierresTombales.valides(out, maintenant: maintenant, ttl: ttl) == [u1])
    }

    @Test("borne exacte du ttl : à la limite reste valide")
    func borneTTL() {
        let raw = [u1.uuidString: maintenant.timeIntervalSince1970 - ttl]  // pile ttl
        #expect(PierresTombales.valides(raw, maintenant: maintenant, ttl: ttl) == [u1])
    }
}
