import Foundation
import Testing
@testable import WelloKit

@Suite("DemandeAvis")
struct DemandeAvisTests {

    private let maintenant = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Sous le seuil d'objectifs atteints, on ne demande rien")
    func sousLeSeuil() {
        for n in 0..<DemandeAvis.seuilObjectifs {
            let état = ÉtatDemandeAvis(objectifsAtteints: n)
            #expect(DemandeAvis.doitDemander(état: état, versionCourante: "1.0", maintenant: maintenant) == false)
        }
    }

    @Test("Au seuil, première sollicitation autorisée")
    func auSeuil() {
        let état = ÉtatDemandeAvis(objectifsAtteints: DemandeAvis.seuilObjectifs)
        #expect(DemandeAvis.doitDemander(état: état, versionCourante: "1.0", maintenant: maintenant))
    }

    @Test("Jamais deux fois sur la même version")
    func mêmeVersion() {
        let état = ÉtatDemandeAvis(objectifsAtteints: 50,
                                   dernièreDemande: maintenant.addingTimeInterval(-DemandeAvis.délaiMinimum * 2),
                                   versionDemandée: "1.0",
                                   nombreDemandes: 1)
        #expect(DemandeAvis.doitDemander(état: état, versionCourante: "1.0", maintenant: maintenant) == false)
        // Une nouvelle version rouvre le droit (délai déjà écoulé).
        #expect(DemandeAvis.doitDemander(état: état, versionCourante: "1.1", maintenant: maintenant))
    }

    @Test("Le délai minimum est respecté, même sur une nouvelle version")
    func délaiMinimum() {
        let état = ÉtatDemandeAvis(objectifsAtteints: 50,
                                   dernièreDemande: maintenant.addingTimeInterval(-DemandeAvis.délaiMinimum + 1),
                                   versionDemandée: "1.0",
                                   nombreDemandes: 1)
        #expect(DemandeAvis.doitDemander(état: état, versionCourante: "1.1", maintenant: maintenant) == false)

        let pileÀLécheance = maintenant.addingTimeInterval(DemandeAvis.délaiMinimum - 1)
        #expect(DemandeAvis.doitDemander(état: état, versionCourante: "1.1", maintenant: pileÀLécheance))
    }

    @Test("Plafond de sollicitations sur la vie de l'app")
    func plafond() {
        let état = ÉtatDemandeAvis(objectifsAtteints: 500,
                                   dernièreDemande: maintenant.addingTimeInterval(-DemandeAvis.délaiMinimum * 10),
                                   versionDemandée: "1.9",
                                   nombreDemandes: DemandeAvis.maxDemandes)
        #expect(DemandeAvis.doitDemander(état: état, versionCourante: "2.0", maintenant: maintenant) == false)
    }

    @Test("Le cycle complet consomme la demande et bloque la suivante")
    func cycleComplet() {
        var état = ÉtatDemandeAvis()
        for _ in 0..<DemandeAvis.seuilObjectifs {
            état = DemandeAvis.aprèsObjectifAtteint(état: état)
        }
        #expect(DemandeAvis.doitDemander(état: état, versionCourante: "1.0", maintenant: maintenant))

        état = DemandeAvis.aprèsDemande(état: état, versionCourante: "1.0", maintenant: maintenant)
        #expect(état.nombreDemandes == 1)
        #expect(état.versionDemandée == "1.0")
        // Objectif suivant : la règle ne redéclenche pas.
        état = DemandeAvis.aprèsObjectifAtteint(état: état)
        #expect(DemandeAvis.doitDemander(état: état, versionCourante: "1.0", maintenant: maintenant) == false)
    }

    @Test("L'état survit à un aller-retour JSON (persistance UserDefaults)")
    func codable() throws {
        let état = ÉtatDemandeAvis(objectifsAtteints: 4,
                                   dernièreDemande: maintenant,
                                   versionDemandée: "1.2",
                                   nombreDemandes: 2)
        let données = try JSONEncoder().encode(état)
        #expect(try JSONDecoder().decode(ÉtatDemandeAvis.self, from: données) == état)
    }
}
