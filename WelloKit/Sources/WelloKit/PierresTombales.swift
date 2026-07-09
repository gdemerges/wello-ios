import Foundation

/// Logique pure des « pierres tombales » d'import : les UUID d'échantillons HealthKit externes
/// supprimés, à ne pas réimporter tant qu'ils restent dans la fenêtre d'import journalière.
/// Stockées en brut `uuidString -> epoch` (UserDefaults côté app) ; ici, purge et lecture testables.
public enum PierresTombales {
    /// UUID encore valides (horodatage ≥ maintenant − ttl). Ignore les clés non-UUID.
    public static func valides(_ raw: [String: Double], maintenant: Date, ttl: TimeInterval) -> Set<UUID> {
        let limite = maintenant.addingTimeInterval(-ttl).timeIntervalSince1970
        return Set(raw.compactMap { clé, epoch in
            epoch >= limite ? UUID(uuidString: clé) : nil
        })
    }

    /// Brut purgé des entrées expirées, avec `uuid` ajouté (horodaté à `maintenant`).
    public static func enAjoutant(_ uuid: UUID, à raw: [String: Double],
                                  maintenant: Date, ttl: TimeInterval) -> [String: Double] {
        let limite = maintenant.addingTimeInterval(-ttl).timeIntervalSince1970
        var out = raw.filter { $0.value >= limite }
        out[uuid.uuidString] = maintenant.timeIntervalSince1970
        return out
    }
}
