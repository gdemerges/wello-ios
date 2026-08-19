import Foundation

/// Compteurs persistés qui pilotent la demande d'avis App Store.
/// Volontairement `Codable` et sans dépendance : la couche app se contente de le stocker.
public struct ÉtatDemandeAvis: Sendable, Equatable, Codable {
    /// Nombre d'objectifs quotidiens atteints depuis l'installation.
    public var objectifsAtteints: Int
    /// Date de la dernière sollicitation effectivement déclenchée.
    public var dernièreDemande: Date?
    /// Version de l'app lors de la dernière sollicitation (jamais deux fois la même).
    public var versionDemandée: String?
    /// Nombre total de sollicitations déclenchées.
    public var nombreDemandes: Int

    public init(objectifsAtteints: Int = 0,
                dernièreDemande: Date? = nil,
                versionDemandée: String? = nil,
                nombreDemandes: Int = 0) {
        self.objectifsAtteints = objectifsAtteints
        self.dernièreDemande = dernièreDemande
        self.versionDemandée = versionDemandée
        self.nombreDemandes = nombreDemandes
    }
}

/// Décide *quand* solliciter un avis App Store. Logique pure : la couche app n'a plus qu'à
/// appeler `requestReview` quand cette règle dit oui.
///
/// La sollicitation se fait sur un **moment positif** (objectif du jour atteint), jamais à
/// l'ouverture : c'est ce qui distingue une note à 5 étoiles d'un 1 étoile d'agacement.
/// Les garde-fous sont plus stricts que ceux d'iOS (qui plafonne déjà à 3 invites/365 j) :
/// l'identité calme de Wello interdit d'insister.
public enum DemandeAvis {
    /// Nombre d'objectifs atteints avant la toute première sollicitation : assez pour que
    /// l'utilisateur ait une opinion, assez tôt pour attraper l'enthousiasme du début.
    public static let seuilObjectifs = 3
    /// Délai minimal entre deux sollicitations.
    public static let délaiMinimum: TimeInterval = 120 * 24 * 3600
    /// Plafond sur toute la vie de l'app, toutes versions confondues.
    public static let maxDemandes = 3

    /// Vrai si l'on peut solliciter un avis maintenant.
    public static func doitDemander(état: ÉtatDemandeAvis,
                                    versionCourante: String,
                                    maintenant: Date) -> Bool {
        guard état.objectifsAtteints >= seuilObjectifs else { return false }
        guard état.nombreDemandes < maxDemandes else { return false }
        // Jamais deux fois sur la même version : une mise à jour est le seul évènement qui
        // justifie de redemander (l'utilisateur a du nouveau à juger).
        guard état.versionDemandée != versionCourante else { return false }
        if let dernière = état.dernièreDemande {
            guard maintenant.timeIntervalSince(dernière) >= délaiMinimum else { return false }
        }
        return true
    }

    /// Nouvel état après une sollicitation déclenchée.
    public static func aprèsDemande(état: ÉtatDemandeAvis,
                                    versionCourante: String,
                                    maintenant: Date) -> ÉtatDemandeAvis {
        var suivant = état
        suivant.dernièreDemande = maintenant
        suivant.versionDemandée = versionCourante
        suivant.nombreDemandes += 1
        return suivant
    }

    /// Nouvel état après un objectif quotidien atteint.
    public static func aprèsObjectifAtteint(état: ÉtatDemandeAvis) -> ÉtatDemandeAvis {
        var suivant = état
        suivant.objectifsAtteints += 1
        return suivant
    }
}
