import Foundation

/// Features pouvant être réservées à Wello+. Couvre dès maintenant tout le périmètre prévu
/// pour que chaque feature ultérieure n'ait qu'à brancher son gating, sans toucher l'infra.
public enum PremiumFeature: String, Sendable, CaseIterable {
    case unlimitedHistory
    case analytics
    case customDrinks
    case advancedTuning
    case export
    case themes
    case adaptiveReminders
    case widget
}

/// Palier d'accès de l'utilisateur.
public enum EntitlementStatus: Sendable, Equatable {
    case free
    case plus
}

/// Table palier → features, en un seul endroit testable.
/// Le cœur gratuit (calcul, saisie, jauge, historique 7 j) n'est pas une `PremiumFeature`.
public struct Entitlements: Sendable {
    public let status: EntitlementStatus

    public init(status: EntitlementStatus) {
        self.status = status
    }

    public func isUnlocked(_ feature: PremiumFeature) -> Bool {
        switch status {
        case .plus: return true
        case .free: return false
        }
    }
}

/// Borne basse de l'historique visible. `nil` = illimité (Wello+).
/// En gratuit : début du jour 6 jours avant aujourd'hui → 7 jours calendaires inclus.
public func historyVisibleSince(status: EntitlementStatus,
                                now: Date,
                                calendar: Calendar = .current) -> Date? {
    switch status {
    case .plus:
        return nil
    case .free:
        let débutAujourdhui = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -6, to: débutAujourdhui)
    }
}
