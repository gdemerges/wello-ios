/// Famille de boisson pour des synthèses lisibles sans perdre le détail par type.
public enum DrinkFamily: String, Sendable, CaseIterable {
    case water
    case caffeine
    case alcohol
    case sweet
    case other

    public var label: String {
        switch self {
        case .water: return "Eau"
        case .caffeine: return "Café / thé"
        case .alcohol: return "Alcool"
        case .sweet: return "Boissons sucrées"
        case .other: return "Autres"
        }
    }
}

public extension DrinkType {
    var family: DrinkFamily {
        switch self {
        case .water, .sparkling:
            return .water
        case .tea, .coffee:
            return .caffeine
        case .alcohol, .beer, .wine, .spirits:
            return .alcohol
        case .juice, .soda, .energy:
            return .sweet
        case .herbalTea, .milk:
            return .other
        }
    }
}

public struct DrinkStatsEntry: Sendable, Equatable {
    public let drink: DrinkType
    public let volumeML: Int
    public let effectiveML: Int
    public let hour: Int

    public init(drink: DrinkType, volumeML: Int, effectiveML: Int, hour: Int) {
        self.drink = drink
        self.volumeML = volumeML
        self.effectiveML = effectiveML
        self.hour = hour
    }
}

public struct DrinkStat: Sendable, Equatable, Identifiable {
    public let drink: DrinkType
    public let family: DrinkFamily
    public let count: Int
    public let volumeML: Int
    public let effectiveML: Int
    public let dominantPeriod: DayPeriod?

    public var id: String { drink.rawValue }

    public init(drink: DrinkType, family: DrinkFamily, count: Int,
                volumeML: Int, effectiveML: Int, dominantPeriod: DayPeriod?) {
        self.drink = drink
        self.family = family
        self.count = count
        self.volumeML = volumeML
        self.effectiveML = effectiveML
        self.dominantPeriod = dominantPeriod
    }
}

public struct DrinkFamilyStat: Sendable, Equatable, Identifiable {
    public let family: DrinkFamily
    public let count: Int
    public let volumeML: Int
    public let effectiveML: Int
    public let dominantPeriod: DayPeriod?

    public var id: String { family.rawValue }

    public init(family: DrinkFamily, count: Int, volumeML: Int,
                effectiveML: Int, dominantPeriod: DayPeriod?) {
        self.family = family
        self.count = count
        self.volumeML = volumeML
        self.effectiveML = effectiveML
        self.dominantPeriod = dominantPeriod
    }
}

public enum DrinkStats {
    public static func byDrink(_ entries: [DrinkStatsEntry]) -> [DrinkStat] {
        let grouped = Dictionary(grouping: entries, by: \.drink)
        return grouped.map { drink, values in
            DrinkStat(drink: drink, family: drink.family, count: values.count,
                      volumeML: values.reduce(0) { $0 + max(0, $1.volumeML) },
                      effectiveML: values.reduce(0) { $0 + $1.effectiveML },
                      dominantPeriod: dominantPeriod(values))
        }
        .sorted {
            if $0.effectiveML != $1.effectiveML { return $0.effectiveML > $1.effectiveML }
            return $0.volumeML > $1.volumeML
        }
    }

    public static func byFamily(_ entries: [DrinkStatsEntry]) -> [DrinkFamilyStat] {
        let grouped = Dictionary(grouping: entries, by: { $0.drink.family })
        return DrinkFamily.allCases.compactMap { family in
            guard let values = grouped[family], !values.isEmpty else { return nil }
            return DrinkFamilyStat(family: family, count: values.count,
                                   volumeML: values.reduce(0) { $0 + max(0, $1.volumeML) },
                                   effectiveML: values.reduce(0) { $0 + $1.effectiveML },
                                   dominantPeriod: dominantPeriod(values))
        }
    }

    private static func dominantPeriod(_ entries: [DrinkStatsEntry]) -> DayPeriod? {
        guard !entries.isEmpty else { return nil }
        var volumes: [DayPeriod: Int] = [:]
        for entry in entries {
            volumes[DayPeriod.from(hour: entry.hour), default: 0] += max(0, entry.volumeML)
        }
        return volumes.max {
            if $0.value != $1.value { return $0.value < $1.value }
            return DayPeriod.allCases.firstIndex(of: $0.key)! > DayPeriod.allCases.firstIndex(of: $1.key)!
        }?.key
    }
}
