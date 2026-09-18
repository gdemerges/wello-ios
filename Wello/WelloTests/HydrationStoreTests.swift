//
//  HydrationStoreTests.swift
//  WelloTests
//
//  Tests d'intégration de l'orchestrateur `HydrationStore` (cible app, SwiftData) : ce que
//  `swift test` sur WelloKit ne couvre pas (calcul pur testé là-bas). Ici on branche le store
//  sur un conteneur SwiftData en mémoire + les mocks de services, et on vérifie le câblage réel :
//  calcul + upsert de l'objectif, comptage du consommé, coefficients, annulation, déduplication
//  des imports HealthKit / prises Watch, et pierres tombales.
//
//  Nécessite la cible « WelloTests » (Unit Testing Bundle, hôte = app). Lancé par Cmd+U dans
//  Xcode et par le job `xcodebuild test` de la CI.
//

import Testing
import Foundation
import SwiftData
import WelloKit
@testable import Wello

@MainActor
struct HydrationStoreTests {

    // MARK: Fabriques

    /// Conteneur SwiftData vierge, 100 % en mémoire (isolé, jetable).
    private func contexteVierge() -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: UserProfile.self, DailyGoal.self, HydrationLog.self,
                                            configurations: config)
        return ModelContext(container)
    }

    private func store(_ ctx: ModelContext,
                       healthKit: HealthKitServicing = MockHealthKitService(),
                       weather: WeatherServicing = MockWeatherService(),
                       adaptatif: Bool = false) -> HydrationStore {
        HydrationStore(modelContext: ctx, healthKit: healthKit, weather: weather,
                       location: MockLocationService(), notifications: MockNotificationService(),
                       watchSync: MockWatchSync(), rappelsAdaptatifsDébloqués: { adaptatif })
    }

    /// Store dont l'objectif ne dépend que de la base EFSA (activité 0, pas de météo) → déterministe.
    private func storeBaseSeule(_ ctx: ModelContext, sexe: BiologicalSex) -> HydrationStore {
        var hk = MockHealthKitService(); hk.énergieKcal = 0
        var w = MockWeatherService(); w.snapshot = nil
        let s = store(ctx, healthKit: hk, weather: w)
        s.profilCourant().sexe = sexe
        return s
    }

    private func logs(_ ctx: ModelContext) -> [HydrationLog] {
        (try? ctx.fetch(FetchDescriptor<HydrationLog>())) ?? []
    }

    // MARK: Objectif

    @Test func aucunObjectifSansSexe() async {
        let ctx = contexteVierge()
        let s = store(ctx)                       // profil créé sans sexe
        await s.refreshToday(force: true)
        #expect(s.breakdown == nil)
    }

    @Test func objectifBaseHomme() async {
        let ctx = contexteVierge()
        let s = storeBaseSeule(ctx, sexe: .homme)
        await s.refreshToday(force: true)
        #expect(s.breakdown?.baseML == 2000)
        #expect(s.breakdown?.totalML == 2000)

        // L'objectif est persisté en un unique DailyGoal du jour.
        let goals = (try? ctx.fetch(FetchDescriptor<DailyGoal>())) ?? []
        #expect(goals.count == 1)
        #expect(goals.first?.totalML == 2000)
    }

    @Test func objectifIntègreActivitéEtMétéo() async {
        let ctx = contexteVierge()
        var hk = MockHealthKitService(); hk.énergieKcal = 300          // +300 ml (1 ml/kcal)
        var w = MockWeatherService()
        w.snapshot = WeatherSnapshot(apparentTemperatureC: 33)         // (33-27)*50 = +300 ml
        let s = store(ctx, healthKit: hk, weather: w)
        s.profilCourant().sexe = .homme
        await s.refreshToday(force: true)
        #expect(s.breakdown?.activityBonusML == 300)
        #expect(s.breakdown?.weatherBonusML == 300)
        #expect(s.breakdown?.totalML == 2600)
    }

    @Test func refreshRéécritLeMêmeDailyGoal() async {
        let ctx = contexteVierge()
        let s = storeBaseSeule(ctx, sexe: .homme)
        await s.refreshToday(force: true)
        await s.refreshToday(force: true)                             // un 2ᵉ calcul le même jour
        let goals = (try? ctx.fetch(FetchDescriptor<DailyGoal>())) ?? []
        #expect(goals.count == 1)                                     // upsert, pas d'insertion en double
    }

    // MARK: Consommé

    @Test func consomméSommeLesPrises() async {
        let ctx = contexteVierge()
        let s = storeBaseSeule(ctx, sexe: .homme)
        await s.log(ml: 250)
        await s.log(ml: 300)
        #expect(s.consomméAujourdhui == 550)
    }

    @Test func consomméAppliqueLeCoefficient() async {
        let ctx = contexteVierge()
        let s = storeBaseSeule(ctx, sexe: .homme)
        await s.log(ml: 200, drink: .coffee, coefficient: 0.8)        // 200 × 0,8 = 160 ml effectifs
        #expect(s.consomméAujourdhui == 160)
    }

    @Test func consomméNeDescendJamaisSousZéro() async {
        let ctx = contexteVierge()
        let s = storeBaseSeule(ctx, sexe: .homme)
        await s.log(ml: 100, drink: .spirits, coefficient: -0.5)      // effectif -50 → borné à 0
        #expect(s.consomméAujourdhui == 0)
    }

    @Test func annulerRetireLaDernièrePrise() async {
        let ctx = contexteVierge()
        let s = storeBaseSeule(ctx, sexe: .homme)
        await s.log(ml: 250)
        await s.log(ml: 500)
        await s.annulerDernièrePrise()
        #expect(s.consomméAujourdhui == 250)
        #expect(logs(ctx).count == 1)
    }

    // MARK: Déduplication

    /// Mock HealthKit qui expose des prises « externes » configurables (imports d'autres apps/Watch).
    private struct HKExternes: HealthKitServicing {
        var externes: [PriseEauExterne] = []
        func requestAuthorization() async {}
        func énergieActiveDuJour() async -> Double { 0 }
        func écrireEau(ml: Int, date: Date) async -> UUID? { nil }
        func supprimerEau(uuid: UUID?, ml: Int, date: Date) async {}
        func prisesEauExternes(depuis date: Date) async -> [PriseEauExterne] { externes }
        func dernierWorkoutTerminé() async -> Date? { nil }
        func périodesSommeil(depuis date: Date) async -> [PériodeSommeil] { [] }
        func supprimerToutesNosPrisesEau() async {}
        func observerEnArrièrePlan(_ surChangement: @escaping @Sendable () async -> Void) {}
    }

    @Test func importHealthKitDédupliquéParUUID() async {
        let ctx = contexteVierge()
        let id = UUID()
        var w = MockWeatherService(); w.snapshot = nil
        let hk = HKExternes(externes: [PriseEauExterne(id: id, ml: 200, date: .now)])
        let s = store(ctx, healthKit: hk, weather: w)
        s.profilCourant().sexe = .homme

        await s.refreshToday(force: true)
        #expect(logs(ctx).count == 1)
        #expect(logs(ctx).first?.healthKitUUID == id)

        await s.refreshToday(force: true)                            // même échantillon → pas de doublon
        #expect(logs(ctx).count == 1)
    }

    @Test func priseWatchDédupliquéeParWatchUUID() async {
        let ctx = contexteVierge()
        let s = storeBaseSeule(ctx, sexe: .homme)
        let prise = PriseWatch(id: UUID(), amountML: 250, loggedAt: .now)
        await s.enregistrerPriseDistante(prise)
        await s.enregistrerPriseDistante(prise)                      // même id → une seule prise
        let watchLogs = logs(ctx).filter { $0.watchUUID != nil }
        #expect(watchLogs.count == 1)
        #expect(s.consomméAujourdhui == 250)
    }

    @Test func supprimerUnImportPoseUnePierreTombale() async {
        let ctx = contexteVierge()
        let id = UUID()
        var w = MockWeatherService(); w.snapshot = nil
        let hk = HKExternes(externes: [PriseEauExterne(id: id, ml: 200, date: .now)])
        let s = store(ctx, healthKit: hk, weather: w)
        s.profilCourant().sexe = .homme

        await s.refreshToday(force: true)
        #expect(logs(ctx).count == 1)

        // On supprime l'import, puis on re-rafraîchit : il ne doit PAS ressusciter le même jour.
        if let importé = logs(ctx).first { await s.supprimer(importé) }
        #expect(logs(ctx).isEmpty)
        await s.refreshToday(force: true)
        #expect(logs(ctx).isEmpty)
    }

    // MARK: Consommé dénormalisé sur le jour

    private func goal(_ ctx: ModelContext, _ jour: Date = .now) -> DailyGoal? {
        let début = Calendar.current.startOfDay(for: jour)
        return try? ctx.fetch(FetchDescriptor<DailyGoal>(predicate: #Predicate { $0.date == début })).first
    }

    /// L'historique et les analyses lisent `DailyGoal.consumedML` au lieu de réagréger les prises :
    /// la colonne doit suivre chaque mutation, sinon les écrans affichent un « bu » périmé.
    @Test func leJourPorteSonConsommé() async {
        let ctx = contexteVierge()
        let s = storeBaseSeule(ctx, sexe: .homme)
        await s.refreshToday(force: true)
        #expect(goal(ctx)?.consumedML == 0)

        await s.log(ml: 250)
        await s.log(ml: 300)
        #expect(goal(ctx)?.consumedML == 550)

        await s.annulerDernièrePrise()
        #expect(goal(ctx)?.consumedML == 250)
    }

    /// Une prise supprimée depuis le détail d'un jour **passé** doit resynchroniser ce jour-là,
    /// pas seulement aujourd'hui.
    @Test func supprimerUnePriseDHierResynchroniseHier() async {
        let ctx = contexteVierge()
        let s = storeBaseSeule(ctx, sexe: .homme)
        let hier = Calendar.current.startOfDay(
            for: Calendar.current.date(byAdding: .day, value: -1, to: .now)!)
        ctx.insert(DailyGoal(date: hier, baseML: 2000, activityBonusML: 0, weatherBonusML: 0,
                             totalML: 2000, consumedML: 800))
        let prise = HydrationLog(amountML: 800, loggedAt: hier.addingTimeInterval(3600))
        ctx.insert(prise)

        await s.supprimer(prise)
        #expect(goal(ctx, hier)?.consumedML == 0)
    }

    /// Le consommé mémoïsé est amorcé depuis le store à la construction (prises déjà en base
    /// avant le premier `refreshToday`, ex. écrites par le widget pendant que l'app était fermée).
    @Test func consomméAmorcéÀLaConstruction() async {
        let ctx = contexteVierge()
        ctx.insert(HydrationLog(amountML: 400))
        let s = storeBaseSeule(ctx, sexe: .homme)
        #expect(s.consomméAujourdhui == 400)
    }
}
