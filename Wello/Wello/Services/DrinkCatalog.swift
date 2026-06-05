import Foundation
import Observation
import WelloKit

/// Coefficients d'hydratation par boisson : défauts de `WelloKit` + overrides utilisateur
/// persistés en `UserDefaults`. Injecté via `.environment` (comme `EntitlementStore`).
/// L'édition est réservée à Wello+ ; la lecture sert aussi à snapshoter le coefficient au log.
@MainActor
@Observable
final class DrinkCatalog {
    private let defaults: UserDefaults
    /// Overrides en mémoire (rawValue → coefficient), miroir de `UserDefaults`.
    private var overrides: [String: Double]

    private static let key = "wello.drinks.coefficients"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.overrides = (defaults.dictionary(forKey: Self.key) as? [String: Double]) ?? [:]
    }

    /// Coefficient résolu (override éventuel sinon défaut), borné à `coefficientRange`.
    func coefficient(for drink: DrinkType) -> Double {
        resolveCoefficient(default: drink.defaultCoefficient, override: overrides[drink.rawValue])
    }

    /// Vrai si l'utilisateur a personnalisé ce coefficient.
    func isCustomized(_ drink: DrinkType) -> Bool {
        overrides[drink.rawValue] != nil
    }

    /// Définit un override (borné) et persiste.
    func setCoefficient(_ valeur: Double, for drink: DrinkType) {
        overrides[drink.rawValue] = resolveCoefficient(default: valeur, override: nil)
        persist()
    }

    /// Réinitialise au coefficient par défaut.
    func reset(_ drink: DrinkType) {
        overrides[drink.rawValue] = nil
        persist()
    }

    private func persist() {
        defaults.set(overrides, forKey: Self.key)
    }
}
