import Foundation
import SwiftData

/// Profil unique de l'utilisateur (app mono-utilisateur).
@Model
final class UserProfile {
    var weightKg: Double
    /// Plancher médical fixe (ex. 2500 ml) — suivi de calculs rénaux calciques.
    var medicalFloorML: Int
    var remindersEnabled: Bool
    /// Montants des 3 boutons d'ajout rapide (personnalisables). Défauts inline pour
    /// la migration légère SwiftData.
    var quickAdd1: Int = 150
    var quickAdd2: Int = 250
    var quickAdd3: Int = 500
    var updatedAt: Date

    /// Les 3 montants rapides dans l'ordre, pour itération en UI.
    var quickAdds: [Int] { [quickAdd1, quickAdd2, quickAdd3] }

    init(weightKg: Double = 75, medicalFloorML: Int = 2500,
         remindersEnabled: Bool = true,
         quickAdd1: Int = 150, quickAdd2: Int = 250, quickAdd3: Int = 500,
         updatedAt: Date = .now) {
        self.weightKg = weightKg
        self.medicalFloorML = medicalFloorML
        self.remindersEnabled = remindersEnabled
        self.quickAdd1 = quickAdd1
        self.quickAdd2 = quickAdd2
        self.quickAdd3 = quickAdd3
        self.updatedAt = updatedAt
    }
}
