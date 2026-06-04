import Foundation

/// Tranches de la journée pour la répartition horaire des prises d'eau.
/// L'ordre de déclaration est l'ordre canonique d'affichage (matin → nuit).
public enum DayPeriod: String, Sendable, CaseIterable {
    case matin       // 6–11
    case midi        // 11–14
    case apresMidi   // 14–18
    case soiree      // 18–23
    case nuit        // 23–6 (enveloppe minuit)

    /// Tranche correspondant à une heure (0…23).
    public static func from(hour: Int) -> DayPeriod {
        switch hour {
        case 6..<11:  return .matin
        case 11..<14: return .midi
        case 14..<18: return .apresMidi
        case 18..<23: return .soiree
        default:      return .nuit   // 23 et 0–5
        }
    }

    /// Libellé court français pour l'affichage.
    public var label: String {
        switch self {
        case .matin:     return "Matin"
        case .midi:      return "Midi"
        case .apresMidi: return "Après-midi"
        case .soiree:    return "Soirée"
        case .nuit:      return "Nuit"
        }
    }
}
