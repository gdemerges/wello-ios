/// Analyse pure d'une prévision à plusieurs jours (J+1…J+3) : signale le premier jour à chaleur
/// notable, pour préparer sa gourde en avance plutôt que découvrir le bonus le jour même.
public enum TendanceMétéo {
    /// Premier jour de `prévisions` (ordonné du plus proche au plus lointain) dont la ressentie
    /// dépasse `seuilC` — celui qui justifie une alerte. `nil` si aucun jour ne dépasse.
    /// Réutilise le seuil de confort du calcul de l'objectif (`HydrationCalculator.Constantes`)
    /// par défaut : un jour qui déclencherait déjà le bonus météo mérite la même alerte à l'avance.
    public static func premierJourChaud(
        _ prévisions: [PrévisionJour],
        seuilC: Double = HydrationCalculator.Constantes.seuilConfortRessentiC
    ) -> PrévisionJour? {
        prévisions.first { $0.apparentTemperatureC > seuilC }
    }
}
