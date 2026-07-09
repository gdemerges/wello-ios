import Foundation

/// Position de l'utilisateur par rapport au rythme attendu dans sa fenêtre d'éveil.
public enum HydrationPaceStatus: Sendable, Equatable {
    case notStarted
    case onTrack
    case behind
    case ahead
    case done
}

/// Rythme intra-journée : objectif linéarisé entre le réveil et le coucher.
/// Purement indicatif : l'objectif réel et les plafonds médicaux restent portés par `GoalBreakdown`.
public struct HydrationPace: Sendable, Equatable {
    public let expectedNowML: Int
    public let remainingML: Int
    public let glassesToGo: Int
    public let minutesUntilBed: Int
    public let status: HydrationPaceStatus

    public init(expectedNowML: Int, remainingML: Int, glassesToGo: Int,
                minutesUntilBed: Int, status: HydrationPaceStatus) {
        self.expectedNowML = expectedNowML
        self.remainingML = remainingML
        self.glassesToGo = glassesToGo
        self.minutesUntilBed = minutesUntilBed
        self.status = status
    }
}

public enum HydrationPaceCalculator {
    /// Tolérance autour du rythme attendu : sous ce seuil, on évite de dramatiser un petit retard.
    public static let toleranceML = 250

    public static func evaluate(goalML: Int, consumedML: Int, now: Date,
                                window: FenêtreÉveil = .défaut, glassML: Int = 250,
                                calendar: Calendar = .current) -> HydrationPace {
        guard goalML > 0 else {
            return HydrationPace(expectedNowML: 0, remainingML: 0, glassesToGo: 0,
                                 minutesUntilBed: 0, status: .notStarted)
        }

        let minute = AdaptiveReminderPlanner.minuteDuJour(now, calendar)
        let span = max(1, window.coucherMin - window.réveilMin)
        let elapsed = min(max(minute - window.réveilMin, 0), span)
        let progress = Double(elapsed) / Double(span)
        let expected = Int((Double(goalML) * progress).rounded())
        let remaining = max(0, goalML - consumedML)
        let glasses = remaining == 0 ? 0 : Int(ceil(Double(remaining) / Double(max(1, glassML))))
        let minutesLeft = max(0, window.coucherMin - minute)

        let status: HydrationPaceStatus
        if consumedML >= goalML {
            status = .done
        } else if minute < window.réveilMin {
            status = .notStarted
        } else {
            let delta = consumedML - expected
            if delta < -toleranceML {
                status = .behind
            } else if delta > toleranceML {
                status = .ahead
            } else {
                status = .onTrack
            }
        }

        return HydrationPace(expectedNowML: expected, remainingML: remaining,
                             glassesToGo: glasses, minutesUntilBed: minutesLeft,
                             status: status)
    }
}
