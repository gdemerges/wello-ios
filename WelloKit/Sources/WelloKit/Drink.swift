/// Type de boisson loggable. Chaque cas porte un coefficient d'hydratation de référence
/// (heuristique, éditable côté app). `water` est toujours le 1ᵉʳ cas (défaut).
public enum DrinkType: String, Sendable, CaseIterable {
    case water, sparkling, herbalTea, milk, tea, coffee, juice, soda, energy, beer, wine, spirits

    /// Libellé FR affichable.
    public var label: String {
        switch self {
        case .water: return "Eau"
        case .sparkling: return "Eau gazeuse"
        case .herbalTea: return "Tisane"
        case .milk: return "Lait"
        case .tea: return "Thé"
        case .coffee: return "Café"
        case .juice: return "Jus de fruits"
        case .soda: return "Soda"
        case .energy: return "Boisson énergisante"
        case .beer: return "Bière"
        case .wine: return "Vin"
        case .spirits: return "Spiritueux"
        }
    }

    /// SF Symbol (iOS 17+). Repli neutre acceptable si un symbole manquait à l'exécution.
    public var icon: String {
        switch self {
        case .water: return "drop.fill"
        case .sparkling: return "bubbles.and.sparkles"
        case .herbalTea: return "leaf.fill"
        case .milk, .tea, .coffee: return "cup.and.saucer.fill"
        case .juice, .soda: return "waterbottle.fill"
        case .energy: return "bolt.fill"
        case .beer: return "mug.fill"
        case .wine, .spirits: return "wineglass.fill"
        }
    }

    /// Coefficient d'hydratation de référence (valeur indicative, non médicale).
    public var defaultCoefficient: Double {
        switch self {
        case .water, .sparkling, .herbalTea, .milk: return 1.0
        case .tea: return 0.9
        case .coffee: return 0.8
        case .juice, .soda: return 0.85
        case .energy: return 0.7
        case .beer: return 0.5
        case .wine: return 0.0
        case .spirits: return -0.5
        }
    }
}

/// Bornes d'un coefficient d'hydratation éditable.
public let coefficientRange: ClosedRange<Double> = -1.0...1.5

/// Hydratation effective (ml) d'une prise : `volume × coefficient`, arrondi au plus proche.
/// Peut être négatif (boisson déshydratante).
public func effectiveHydrationML(volumeML: Int, coefficient: Double) -> Int {
    Int((Double(volumeML) * coefficient).rounded())
}

/// Coefficient résolu : l'`override` s'il existe, sinon le `default`, borné à `coefficientRange`.
public func resolveCoefficient(default défaut: Double, override: Double?) -> Double {
    let valeur = override ?? défaut
    return min(max(valeur, coefficientRange.lowerBound), coefficientRange.upperBound)
}

/// « Consommé » affichable d'un jour : jamais négatif (l'alcool peut faire reculer la somme).
public func clampedDayTotal(_ sum: Int) -> Int {
    max(0, sum)
}
