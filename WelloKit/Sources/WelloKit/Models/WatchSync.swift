import Foundation

/// Une prise d'eau saisie au poignet, en attente de synchronisation vers l'iPhone.
/// Transportée par `WCSession.transferUserInfo` (file à livraison garantie) via son codec
/// dictionnaire plist-safe. Pure et testable en CLI.
public struct PriseWatch: Sendable, Equatable, Codable, Identifiable {
    public let id: UUID
    public let amountML: Int
    public let loggedAt: Date

    public init(id: UUID = UUID(), amountML: Int, loggedAt: Date = .init()) {
        self.id = id
        self.amountML = amountML
        self.loggedAt = loggedAt
    }

    /// Dictionnaire plist-safe pour `WCSession` (UUID→String, Date→Double).
    public func dictionnaire() -> [String: Any] {
        ["id": id.uuidString, "amountML": amountML, "loggedAt": loggedAt.timeIntervalSince1970]
    }

    public init?(dictionnaire dict: [String: Any]) {
        guard let ids = dict["id"] as? String, let id = UUID(uuidString: ids),
              let ml = dict["amountML"] as? Int,
              let ts = dict["loggedAt"] as? Double else { return nil }
        self.init(id: id, amountML: ml, loggedAt: Date(timeIntervalSince1970: ts))
    }
}

/// Mirroir d'état poussé par l'iPhone vers la Watch (`updateApplicationContext`, coalescé,
/// dernier-état-gagne). Porte l'objectif/consommé autoritaires, les montants rapides, un profil
/// minimal (pour le recalcul autonome) et l'ensemble des `id` de prises Watch déjà acquittées
/// par l'iPhone (pour purger l'affichage optimiste). Pur et testable en CLI.
public struct WatchSyncSnapshot: Sendable, Equatable, Codable {
    public let objectifML: Int
    public let consomméML: Int
    public let quickAdds: [Int]
    public let configuré: Bool
    public let sexeRaw: String?
    public let etatPhysioRaw: String?
    public let renalBonusML: Int
    public let activitySensitivity: Double
    public let weatherSensitivity: Double
    public let manualAdjustmentML: Int
    public let acquittés: [UUID]
    public let générémLe: Date

    public init(objectifML: Int, consomméML: Int, quickAdds: [Int], configuré: Bool,
                sexeRaw: String?, etatPhysioRaw: String?, renalBonusML: Int,
                activitySensitivity: Double, weatherSensitivity: Double, manualAdjustmentML: Int,
                acquittés: [UUID], générémLe: Date) {
        self.objectifML = objectifML
        self.consomméML = consomméML
        self.quickAdds = quickAdds
        self.configuré = configuré
        self.sexeRaw = sexeRaw
        self.etatPhysioRaw = etatPhysioRaw
        self.renalBonusML = renalBonusML
        self.activitySensitivity = activitySensitivity
        self.weatherSensitivity = weatherSensitivity
        self.manualAdjustmentML = manualAdjustmentML
        self.acquittés = acquittés
        self.générémLe = générémLe
    }

    /// Dictionnaire plist-safe pour `WCSession`. Les optionnels absents sont simplement omis.
    public func dictionnaire() -> [String: Any] {
        var d: [String: Any] = [
            "objectifML": objectifML,
            "consomméML": consomméML,
            "quickAdds": quickAdds,
            "configuré": configuré,
            "renalBonusML": renalBonusML,
            "activitySensitivity": activitySensitivity,
            "weatherSensitivity": weatherSensitivity,
            "manualAdjustmentML": manualAdjustmentML,
            "acquittés": acquittés.map(\.uuidString),
            "générémLe": générémLe.timeIntervalSince1970
        ]
        if let sexeRaw { d["sexeRaw"] = sexeRaw }
        if let etatPhysioRaw { d["etatPhysioRaw"] = etatPhysioRaw }
        return d
    }

    public init?(dictionnaire d: [String: Any]) {
        guard let objectifML = d["objectifML"] as? Int,
              let consomméML = d["consomméML"] as? Int,
              let quickAdds = d["quickAdds"] as? [Int],
              let configuré = d["configuré"] as? Bool,
              let renalBonusML = d["renalBonusML"] as? Int,
              let activitySensitivity = d["activitySensitivity"] as? Double,
              let weatherSensitivity = d["weatherSensitivity"] as? Double,
              let manualAdjustmentML = d["manualAdjustmentML"] as? Int,
              let acquittésRaw = d["acquittés"] as? [String],
              let ts = d["générémLe"] as? Double else { return nil }
        self.init(
            objectifML: objectifML, consomméML: consomméML, quickAdds: quickAdds, configuré: configuré,
            sexeRaw: d["sexeRaw"] as? String, etatPhysioRaw: d["etatPhysioRaw"] as? String,
            renalBonusML: renalBonusML, activitySensitivity: activitySensitivity,
            weatherSensitivity: weatherSensitivity, manualAdjustmentML: manualAdjustmentML,
            acquittés: acquittésRaw.compactMap(UUID.init(uuidString:)),
            générémLe: Date(timeIntervalSince1970: ts))
    }
}
