import Foundation

/// Choisit le poids à utiliser pour le calcul : HealthKit en priorité,
/// sinon le poids saisi dans le profil. Ignore les valeurs non plausibles.
public func résoudrePoids(healthKitKg: Double?, profilKg: Double) -> Double {
    if let hk = healthKitKg, hk > 0 { return hk }
    return profilKg
}
