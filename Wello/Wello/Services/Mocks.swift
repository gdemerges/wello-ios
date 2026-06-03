import Foundation
import WelloKit

/// Implémentations factices pour les SwiftUI previews et le développement hors device.
struct MockHealthKitService: HealthKitServicing {
    var effort: Int = 45
    var poids: Double? = 78
    func requestAuthorization() async {}
    func minutesEffortDuJour() async -> Int { effort }
    func dernierPoids() async -> Double? { poids }
    func écrireEau(ml: Int, date: Date) async {}
    func minutesEffortDepuis(_ date: Date) async -> Int { 0 }
    func dernierWorkoutTerminé() async -> Date? { nil }
}

struct MockWeatherService: WeatherServicing {
    var snapshot: WeatherSnapshot? = WeatherSnapshot(temperatureC: 30, humidityPct: 75)
    func météoDuJour(latitude: Double, longitude: Double) async -> WeatherSnapshot? { snapshot }
}

struct MockLocationService: LocationServicing {
    var coords: (latitude: Double, longitude: Double)? = (48.85, 2.35)
    func coordonnéesActuelles() async -> (latitude: Double, longitude: Double)? { coords }
}

struct MockNotificationService: NotificationServicing {
    func requestAuthorization() async -> Bool { true }
    func planifierRappels(objectifML: Int, consomméML: Int) async {}
    func programmerRappelPostSéance() async {}
    func programmerSnooze() async {}
    func annulerTout() async {}
    func désactiverPourLaJournée() async {}
}
