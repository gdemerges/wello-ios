import Foundation

/// Calcul d'affichage pour les widgets : dérive d'un couple (consommé, objectif) en ml
/// la fraction de remplissage, le pourcentage et les libellés français formatés.
/// Pur et testable en CLI ; ne dépend ni de SwiftUI ni de SwiftData.
public struct WidgetProgress: Sendable, Equatable {
    /// Consommé brut du jour (peut être négatif si des boissons diurétiques sont saisies).
    public let consomméML: Int
    /// Objectif du jour (0 si non encore calculé / non configuré).
    public let objectifML: Int

    public init(consomméML: Int, objectifML: Int) {
        self.consomméML = consomméML
        self.objectifML = objectifML
    }

    /// Consommé borné à 0 (un total négatif n'a pas de sens pour l'affichage).
    private var consomméClampé: Int { max(0, consomméML) }

    /// Fraction de remplissage bornée 0…1 (pour l'anneau / la barre).
    public var fraction: Double {
        guard objectifML > 0 else { return 0 }
        return min(1, Double(consomméClampé) / Double(objectifML))
    }

    /// Pourcentage réel, arrondi (peut dépasser 100 ; 0 si objectif nul).
    public var pourcent: Int {
        guard objectifML > 0 else { return 0 }
        return Int((Double(consomméClampé) / Double(objectifML) * 100).rounded())
    }

    /// Litres consommés, un chiffre après la virgule décimale française. Ex. "1,4".
    public var consomméLitres: String { Self.litres(consomméClampé) }
    /// Litres de l'objectif, format français. Ex. "2,3".
    public var objectifLitres: String { Self.litres(objectifML) }

    /// "1,4 / 2,3 L"
    public var libelléValeurs: String { "\(consomméLitres) / \(objectifLitres) L" }
    /// "61 %"
    public var libelléPourcent: String { "\(pourcent) %" }

    /// Formate des ml en litres « x,y » indépendamment de la locale système (déterministe).
    private static func litres(_ ml: Int) -> String {
        let liters = Double(ml) / 1000
        let rounded = (liters * 10).rounded() / 10
        let s = String(format: "%.1f", rounded)
        return s.replacingOccurrences(of: ".", with: ",")
    }
}
