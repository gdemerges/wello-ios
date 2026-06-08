import Foundation

/// Fenêtre d'éveil quotidienne, en minutes depuis minuit.
public struct FenêtreÉveil: Sendable, Equatable {
    public let réveilMin: Int
    public let coucherMin: Int
    public init(réveilMin: Int, coucherMin: Int) {
        self.réveilMin = réveilMin
        self.coucherMin = coucherMin
    }
    /// Repli ultime quand ni le sommeil ni l'historique ne renseignent la fenêtre.
    public static let défaut = FenêtreÉveil(réveilMin: 7 * 60, coucherMin: 21 * 60)
}

/// Un intervalle de sommeil (source HealthKit, mappé en type pur pour la dérivation testable).
public struct PériodeSommeil: Sendable {
    public let début: Date
    public let fin: Date
    public init(début: Date, fin: Date) {
        self.début = début
        self.fin = fin
    }
}

/// Les prises d'un jour, en minutes depuis minuit (ordre indifférent ; trié à l'usage).
public struct JourDePrises: Sendable {
    public let minutesDePrise: [Int]
    public init(minutesDePrise: [Int]) {
        self.minutesDePrise = minutesDePrise
    }
}

/// Planificateur pur des rappels adaptatifs : apprend les trous d'hydratation récurrents
/// et en déduit des heures de rappel préventives. Aucune dépendance UIKit/HealthKit →
/// entièrement testable via `swift test`.
public struct AdaptiveReminderPlanner: Sendable {
    // Constantes de réglage (documentées, ajustables sans toucher la logique).
    /// Fenêtre d'apprentissage glissante.
    public static let joursHistoire = 14
    /// Données minimales avant d'activer l'adaptatif (sinon rappels fixes).
    public static let minJoursPourAdaptatif = 7
    /// Durée minimale d'un « trou » d'hydratation (minutes).
    static let minGapMin = 120
    /// Fraction des jours où un créneau doit apparaître pour être « habituel ».
    static let seuilRécurrence = 0.40
    /// Anticipation : on rappelle ce nombre de minutes avant d'atteindre le seuil de trou.
    static let leadTimeMin = 15
    /// Espacement minimal entre deux rappels d'une même journée (minutes).
    static let espacementMin = 90
    /// Nombre maximal de rappels adaptatifs par jour.
    public static let plafondParJour = 6

    public init() {}

    /// Vrai si l'historique contient assez de jours non vides pour apprendre.
    public func aAssezDeDonnées(_ historique: [JourDePrises]) -> Bool {
        historique.filter { !$0.minutesDePrise.isEmpty }.count >= Self.minJoursPourAdaptatif
    }

    /// Fenêtre d'éveil déduite des habitudes de prises : réveil ≈ 15ᵉ percentile des 1ʳᵉˢ
    /// prises, coucher ≈ 85ᵉ percentile des dernières. `nil` si aucune donnée exploitable.
    public func fenêtreDepuisHistorique(_ historique: [JourDePrises]) -> FenêtreÉveil? {
        var premières: [Int] = []
        var dernières: [Int] = []
        for jour in historique {
            let triées = jour.minutesDePrise.sorted()
            guard let p = triées.first, let d = triées.last else { continue }
            premières.append(p)
            dernières.append(d)
        }
        guard !premières.isEmpty else { return nil }
        let réveil = Self.clampRéveil(percentile(premières, 15))
        let coucher = Self.clampCoucher(percentile(dernières, 85))
        return FenêtreÉveil(réveilMin: réveil, coucherMin: coucher)
    }

    /// Fenêtre d'éveil déduite du sommeil : réveil = médiane des fins de sommeil (matin),
    /// coucher = médiane des débuts de sommeil (soir). `nil` si aucune période.
    public func fenêtreDepuisSommeil(_ périodes: [PériodeSommeil],
                                     calendar: Calendar = .current) -> FenêtreÉveil? {
        guard !périodes.isEmpty else { return nil }
        let fins = périodes.map { Self.minuteDuJour($0.fin, calendar) }
        let débuts = périodes.map { Self.minuteDuJour($0.début, calendar) }
        return FenêtreÉveil(réveilMin: Self.clampRéveil(médiane(fins)),
                            coucherMin: Self.clampCoucher(médiane(débuts)))
    }

    /// Minutes depuis minuit d'une date dans le calendrier donné.
    static func minuteDuJour(_ date: Date, _ calendar: Calendar) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    // Bornes de sécurité pour ne jamais rappeler en pleine nuit.
    static func clampRéveil(_ m: Int) -> Int { min(max(m, 240), 660) }    // 4:00–11:00
    static func clampCoucher(_ m: Int) -> Int { min(max(m, 1080), 1410) } // 18:00–23:30
}

/// Percentile par rang le plus proche (p ∈ 0...100), sur une liste non vide.
func percentile(_ valeurs: [Int], _ p: Int) -> Int {
    let triées = valeurs.sorted()
    guard triées.count > 1 else { return triées.first ?? 0 }
    let rang = Int((Double(p) / 100.0 * Double(triées.count - 1)).rounded())
    return triées[min(max(rang, 0), triées.count - 1)]
}

/// Médiane entière d'une liste non vide (moyenne basse des deux centraux si pair).
func médiane(_ valeurs: [Int]) -> Int {
    let triées = valeurs.sorted()
    let n = triées.count
    guard n > 0 else { return 0 }
    if n % 2 == 1 { return triées[n / 2] }
    return (triées[n / 2 - 1] + triées[n / 2]) / 2
}
