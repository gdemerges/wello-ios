import Foundation
import WelloKit
import OSLog

/// Récupère la météo du jour via Open-Meteo (gratuit, sans clé). Best-effort : nil sur échec.
struct WeatherService: WeatherServicing {
    /// Session dédiée : `URLSession.shared` attend 60 s par défaut. La météo n'est qu'un bonus du
    /// calcul — sur un réseau dégradé, mieux vaut abandonner vite (objectif sans bonus météo,
    /// déjà géré) que suspendre le rafraîchissement de longues secondes.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        config.waitsForConnectivity = false   // hors ligne = échec immédiat, pas d'attente du réseau
        return URLSession(configuration: config)
    }()

    func météoDuJour(latitude: Double, longitude: Double) async -> WeatherSnapshot? {
        var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        // Minimisation : 2 décimales (~1,1 km) suffisent largement à la météo — on ne transmet
        // pas la position pleine précision au tiers. Locale POSIX : point décimal garanti.
        let arrondi = { String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), $0) }
        comps.queryItems = [
            .init(name: "latitude", value: arrondi(latitude)),
            .init(name: "longitude", value: arrondi(longitude)),
            // Température ressentie max du jour : intègre humidité + vent + rayonnement.
            .init(name: "daily", value: "apparent_temperature_max"),
            .init(name: "forecast_days", value: "1"),
            .init(name: "timezone", value: "auto"),
        ]
        guard let url = comps.url else { return nil }

        do {
            let (data, réponse) = try await Self.session.data(from: url)
            let code = (réponse as? HTTPURLResponse)?.statusCode ?? -1
            guard code == 200 else {
                WelloLog.météo.error("Open-Meteo a répondu \(code, privacy: .public) → bonus météo à 0")
                return nil
            }
            let dto = try JSONDecoder().decode(OpenMeteoDTO.self, from: data)
            guard let ressentieMax = dto.daily.apparent_temperature_max.first else {
                WelloLog.météo.error("réponse Open-Meteo sans température → bonus météo à 0")
                return nil
            }
            // `elevation` (m) est renvoyé par défaut par Open-Meteo : alimente le bonus altitude.
            return WeatherSnapshot(apparentTemperatureC: ressentieMax, altitudeM: dto.elevation)
        } catch {
            // Réseau/API down → météo absente, le calcul tourne quand même (bonus à 0).
            WelloLog.météo.error("appel Open-Meteo échoué : \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func prévisionTroisJours(latitude: Double, longitude: Double) async -> [PrévisionJour]? {
        var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        let arrondi = { String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), $0) }
        comps.queryItems = [
            .init(name: "latitude", value: arrondi(latitude)),
            .init(name: "longitude", value: arrondi(longitude)),
            .init(name: "daily", value: "apparent_temperature_max"),
            .init(name: "forecast_days", value: "4"),   // aujourd'hui (index 0, ignoré) + J+1…J+3
            .init(name: "timezone", value: "auto"),
        ]
        guard let url = comps.url else { return nil }

        do {
            let (data, réponse) = try await Self.session.data(from: url)
            let code = (réponse as? HTTPURLResponse)?.statusCode ?? -1
            guard code == 200 else {
                WelloLog.météo.error("Open-Meteo (prévision) a répondu \(code, privacy: .public)")
                return nil
            }
            let dto = try JSONDecoder().decode(OpenMeteoDTO.self, from: data)
            // Le jour courant (index 0) est déjà couvert par le bonus météo du jour → on ne garde
            // que J+1…J+3, datés localement plutôt que par parsing des dates Open-Meteo.
            let cal = Calendar.current
            let aujourdhui = cal.startOfDay(for: .now)
            return dto.daily.apparent_temperature_max.dropFirst().enumerated().map { décalage, temp in
                let date = cal.date(byAdding: .day, value: décalage + 1, to: aujourdhui) ?? aujourdhui
                return PrévisionJour(date: date, apparentTemperatureC: temp)
            }
        } catch {
            WelloLog.météo.error("appel Open-Meteo (prévision) échoué : \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

/// DTO interne de décodage Open-Meteo.
private struct OpenMeteoDTO: Decodable {
    struct Daily: Decodable { let apparent_temperature_max: [Double] }
    let daily: Daily
    /// Altitude du point (m). Renvoyée par défaut par Open-Meteo ; optionnelle par prudence.
    let elevation: Double?
}
