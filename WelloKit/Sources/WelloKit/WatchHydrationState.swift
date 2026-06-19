import Foundation

/// État d'affichage de l'app Watch, dérivé **purement** d'un snapshot autoritaire (iPhone) et
/// d'une file de prises locales optimistes. Cœur de la réconciliation sans double comptage :
/// `consommé = snapshot.consomméML + Σ prises locales non acquittées`. Pur et testable en CLI.
public struct ÉtatHydratationWatch: Sendable, Equatable {
    /// Dernier mirroir reçu de l'iPhone. `nil` tant que la Watch n'a jamais synchronisé.
    public private(set) var snapshot: WatchSyncSnapshot?
    /// Prises saisies au poignet, persistées jusqu'à acquittement par l'iPhone.
    public private(set) var prisesLocales: [PriseWatch]
    /// Dernière énergie active lue sur la Watch (kcal), pour le recalcul autonome de l'objectif.
    public private(set) var énergieActiveKcal: Double

    public init(snapshot: WatchSyncSnapshot? = nil,
                prisesLocales: [PriseWatch] = [],
                énergieActiveKcal: Double = 0) {
        self.snapshot = snapshot
        self.prisesLocales = prisesLocales
        self.énergieActiveKcal = énergieActiveKcal
    }

    /// Vrai dès que l'iPhone a fourni un objectif configuré.
    public var configuré: Bool { snapshot?.configuré ?? false }

    /// Montants des 3 boutons d'ajout rapide (repli sur les défauts).
    public var quickAdds: [Int] { snapshot?.quickAdds ?? [150, 250, 500] }

    /// Prises pas encore absorbées par l'iPhone (id ∉ acquittés du snapshot).
    public var prisesEnAttente: [PriseWatch] {
        let acquittés = Set(snapshot?.acquittés ?? [])
        return prisesLocales.filter { !acquittés.contains($0.id) }
    }

    /// Consommé affiché : total autoritaire + prises optimistes non acquittées.
    public var consomméML: Int {
        (snapshot?.consomméML ?? 0) + prisesEnAttente.reduce(0) { $0 + $1.amountML }
    }

    /// Objectif affiché : `max(poussé, recalculé)`. La météo reste portée par le poussé (iPhone) ;
    /// la part « activité » peut monter au poignet via l'énergie active locale. 0 si non configuré.
    public var objectifML: Int {
        guard let s = snapshot, s.configuré else { return 0 }
        return max(s.objectifML, objectifRecalculé(s) ?? 0)
    }

    /// Affichage de progression (anneau/%/libellés), réutilise le type widget.
    public var progress: WidgetProgress {
        WidgetProgress(consomméML: consomméML, objectifML: objectifML)
    }

    // MARK: Mutations

    /// Ajoute une prise locale (affichage optimiste immédiat).
    public mutating func ajouterPrise(_ prise: PriseWatch) {
        prisesLocales.append(prise)
    }

    /// Applique un snapshot reçu de l'iPhone et purge les prises locales désormais acquittées.
    public mutating func appliquer(_ s: WatchSyncSnapshot) {
        snapshot = s
        let acquittés = Set(s.acquittés)
        prisesLocales.removeAll { acquittés.contains($0.id) }
    }

    /// Met à jour l'énergie active (kcal) lue sur la Watch.
    public mutating func mettreÀJourÉnergie(_ kcal: Double) {
        énergieActiveKcal = kcal
    }

    /// Retire et renvoie la dernière prise **en attente** (non acquittée). `nil` s'il n'y en a pas.
    @discardableResult
    public mutating func annulerDernièreEnAttente() -> PriseWatch? {
        let acquittés = Set(snapshot?.acquittés ?? [])
        guard let idx = prisesLocales.lastIndex(where: { !acquittés.contains($0.id) }) else { return nil }
        return prisesLocales.remove(at: idx)
    }

    // MARK: Recalcul

    /// Objectif recalculé au poignet depuis le profil du snapshot + l'énergie active locale.
    /// `nil` si le sexe est inconnu (on ne fabrique pas de base sans lui).
    private func objectifRecalculé(_ s: WatchSyncSnapshot) -> Int? {
        guard let sexeRaw = s.sexeRaw, let sexe = BiologicalSex(rawValue: sexeRaw) else { return nil }
        let inputs = CalculatorInputs(
            sex: sexe,
            activeEnergyKcal: énergieActiveKcal,
            weather: nil,   // la météo reste portée par l'objectif poussé
            physiologicalState: s.etatPhysioRaw.flatMap(PhysiologicalState.init(rawValue:)) ?? .aucun,
            renalBonusML: s.renalBonusML,
            tuning: CalculatorTuning(activityMultiplier: s.activitySensitivity,
                                     weatherMultiplier: s.weatherSensitivity,
                                     manualAdjustmentML: s.manualAdjustmentML))
        return HydrationCalculator().calculate(inputs).totalML
    }
}
