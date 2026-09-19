import Foundation

/// Prévision météo d'un jour à venir (J+1…J+3), pour la carte « tendance météo » des Analyses —
/// distincte de `WeatherSnapshot` qui capture le jour courant pour le calcul de l'objectif.
public struct PrévisionJour: Sendable, Equatable, Identifiable {
    public let date: Date
    public let apparentTemperatureC: Double

    public var id: Date { date }

    public init(date: Date, apparentTemperatureC: Double) {
        self.date = date
        self.apparentTemperatureC = apparentTemperatureC
    }
}
