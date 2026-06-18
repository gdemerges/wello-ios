import Foundation
import SwiftData
import WelloKit

/// Profil unique de l'utilisateur (app mono-utilisateur).
@Model
final class UserProfile {
    var remindersEnabled: Bool
    /// Sexe biologique pour la base EFSA. Stocké en brut (String?) pour la migration légère
    /// SwiftData ; nil = pas encore renseigné (force l'onboarding). Exposé via `sexe`.
    var sexeRaw: String? = nil
    /// État physiologique (grossesse/allaitement). Brut pour la migration légère ; nil = aucun.
    var etatPhysioRaw: String? = nil
    /// Suivi rénal (lithiase) : opt-in. Quand actif, ajoute `renalBonusML` à l'objectif.
    var renalLithiase: Bool = false
    /// Apport rénal additif (ml) appliqué quand `renalLithiase` est actif. Réglable 500–1500.
    var renalBonusML: Int = 1000
    /// Montants des 3 boutons d'ajout rapide (personnalisables). Défauts inline pour
    /// la migration légère SwiftData.
    var quickAdd1: Int = 150
    var quickAdd2: Int = 250
    var quickAdd3: Int = 500
    /// Réglage avancé (Wello+). Défauts inline neutres → objectif standard, migration légère.
    var activitySensitivity: Double = 1.0
    var weatherSensitivity: Double = 1.0
    var manualAdjustmentML: Int = 0
    var updatedAt: Date

    /// Les 3 montants rapides dans l'ordre, pour itération en UI.
    var quickAdds: [Int] { [quickAdd1, quickAdd2, quickAdd3] }

    /// Réglage avancé assemblé pour le calcul (borné défensivement par `CalculatorTuning`).
    var tuning: CalculatorTuning {
        CalculatorTuning(activityMultiplier: activitySensitivity,
                         weatherMultiplier: weatherSensitivity,
                         manualAdjustmentML: manualAdjustmentML)
    }

    /// Vrai si le réglage avancé n'est pas neutre (au moins un paramètre modifié).
    var réglageAvancéModifié: Bool { tuning != .neutre }

    /// Sexe biologique, ou nil si non renseigné.
    var sexe: BiologicalSex? {
        get { sexeRaw.flatMap(BiologicalSex.init(rawValue:)) }
        set { sexeRaw = newValue?.rawValue }
    }

    /// État physiologique (défaut : aucun).
    var etatPhysio: PhysiologicalState {
        get { etatPhysioRaw.flatMap(PhysiologicalState.init(rawValue:)) ?? .aucun }
        set { etatPhysioRaw = newValue.rawValue }
    }

    /// Apport rénal effectif appliqué au calcul (0 si le suivi est désactivé).
    var renalBonusEffectifML: Int { renalLithiase ? renalBonusML : 0 }

    init(remindersEnabled: Bool = true,
         quickAdd1: Int = 150, quickAdd2: Int = 250, quickAdd3: Int = 500,
         updatedAt: Date = .now) {
        self.remindersEnabled = remindersEnabled
        self.quickAdd1 = quickAdd1
        self.quickAdd2 = quickAdd2
        self.quickAdd3 = quickAdd3
        self.updatedAt = updatedAt
    }
}
