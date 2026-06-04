/// Total d'un jour : consommé vs objectif. Brique des statistiques d'historique.
public struct DailyTotal: Sendable, Equatable {
    public let consumedML: Int
    public let goalML: Int

    public init(consumedML: Int, goalML: Int) {
        self.consumedML = consumedML
        self.goalML = goalML
    }

    /// Objectif atteint ce jour-là.
    public var reached: Bool { goalML > 0 && consumedML >= goalML }
}

/// Statistiques d'hydratation dérivées d'une suite de jours. Fonctions pures, testables.
public enum HydrationStats {

    /// Série de jours consécutifs ayant atteint l'objectif, en partant du plus récent.
    /// `days` doit être ordonné du plus récent au plus ancien.
    public static func currentStreak(_ days: [DailyTotal]) -> Int {
        var n = 0
        for d in days {
            if d.reached { n += 1 } else { break }
        }
        return n
    }

    /// Moyenne du consommé (ml) sur les `lastN` jours les plus récents.
    /// `days` ordonné du plus récent au plus ancien. 0 si vide.
    public static func averageConsumed(_ days: [DailyTotal], lastN: Int) -> Int {
        let échantillon = Array(days.prefix(max(0, lastN)))
        guard !échantillon.isEmpty else { return 0 }
        return échantillon.reduce(0) { $0 + $1.consumedML } / échantillon.count
    }

    /// Fraction de jours ayant atteint l'objectif (0…1). 0 si la liste est vide.
    /// L'appelant passe la fenêtre voulue, ex. `Array(days.prefix(7))`.
    public static func reachRate(_ days: [DailyTotal]) -> Double {
        guard !days.isEmpty else { return 0 }
        let atteints = days.filter(\.reached).count
        return Double(atteints) / Double(days.count)
    }

    /// Plus longue série de jours consécutifs atteints, sur toute la liste fournie.
    /// Indépendant du sens d'ordre (ne dépend que de la contiguïté dans la liste passée).
    public static func bestStreak(_ days: [DailyTotal]) -> Int {
        var record = 0
        var courant = 0
        for d in days {
            if d.reached {
                courant += 1
                record = max(record, courant)
            } else {
                courant = 0
            }
        }
        return record
    }

    /// Somme des ml par tranche de journée. Renvoie toujours les 5 tranches dans l'ordre
    /// canonique (matin→nuit), à 0 si aucune prise. `entries` = (heure 0…23, ml).
    public static func hydrationByPeriod(_ entries: [(hour: Int, ml: Int)]) -> [(period: DayPeriod, ml: Int)] {
        var sommes: [DayPeriod: Int] = [:]
        for e in entries {
            sommes[DayPeriod.from(hour: e.hour), default: 0] += e.ml
        }
        return DayPeriod.allCases.map { (period: $0, ml: sommes[$0] ?? 0) }
    }
}
