import Foundation

/// Une prise, aplatie pour l'export (découplée de SwiftData).
public struct ExportLogRow: Sendable {
    public let loggedAt: Date
    public let drinkLabel: String
    public let volumeML: Int
    public let coefficient: Double
    public let effectiveML: Int
    /// Provenance brute ("app" / "healthkit").
    public let source: String

    public init(loggedAt: Date, drinkLabel: String, volumeML: Int,
                coefficient: Double, effectiveML: Int, source: String) {
        self.loggedAt = loggedAt
        self.drinkLabel = drinkLabel
        self.volumeML = volumeML
        self.coefficient = coefficient
        self.effectiveML = effectiveML
        self.source = source
    }
}

/// Le bilan d'un jour, aplati pour l'export.
public struct ExportDaySummary: Sendable {
    public let day: Date
    public let consumedML: Int
    public let goalML: Int

    public init(day: Date, consumedML: Int, goalML: Int) {
        self.day = day
        self.consumedML = consumedML
        self.goalML = goalML
    }

    /// Objectif atteint (objectif strictement positif et consommé au moins égal).
    public var reached: Bool { goalML > 0 && consumedML >= goalML }
}

/// Sérialisation CSV de l'historique d'hydratation. Pure et déterministe (testable en CLI) :
/// dates formatées en locale POSIX, séparateur virgule, échappement RFC 4180.
public enum HydrationExport {

    /// CSV détaillé : une ligne par prise. Colonnes FR, horodatage local ISO (sans offset).
    public static func detailCSV(_ rows: [ExportLogRow], timeZone: TimeZone = .current) -> String {
        let formatter = dateTimeFormatter(timeZone)
        let entêtes = ["Horodatage", "Boisson", "Volume (ml)", "Coefficient", "Effectif (ml)", "Source"]
        var lignes = [ligneCSV(entêtes)]
        for r in rows {
            lignes.append(ligneCSV([
                formatter.string(from: r.loggedAt),
                r.drinkLabel,
                String(r.volumeML),
                nombre(r.coefficient),
                String(r.effectiveML),
                r.source,
            ]))
        }
        return lignes.joined(separator: "\r\n")
    }

    /// CSV résumé : une ligne par jour (consommé vs objectif).
    public static func summaryCSV(_ days: [ExportDaySummary], timeZone: TimeZone = .current) -> String {
        let formatter = dateFormatter(timeZone)
        let entêtes = ["Jour", "Consommé (ml)", "Objectif (ml)", "Atteint"]
        var lignes = [ligneCSV(entêtes)]
        for d in days {
            lignes.append(ligneCSV([
                formatter.string(from: d.day),
                String(d.consumedML),
                String(d.goalML),
                d.reached ? "oui" : "non",
            ]))
        }
        return lignes.joined(separator: "\r\n")
    }

    // MARK: - Formatage

    /// Coefficient en notation décimale point, 2 décimales (indépendant de la locale).
    private static func nombre(_ valeur: Double) -> String {
        String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), valeur)
    }

    private static func dateTimeFormatter(_ tz: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = tz
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }

    private static func dateFormatter(_ tz: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = tz
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    /// Assemble une ligne CSV en échappant chaque champ (RFC 4180).
    private static func ligneCSV(_ champs: [String]) -> String {
        champs.map(échapper).joined(separator: ",")
    }

    /// Entoure de guillemets et double les guillemets internes si le champ contient `,`, `"` ou un saut de ligne.
    private static func échapper(_ champ: String) -> String {
        guard champ.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else {
            return champ
        }
        return "\"" + champ.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
