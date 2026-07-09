import SwiftUI
import WelloKit

/// Liens légaux requis par l'App Store pour un achat.
/// Force-unwrap sûr : ce sont des constantes ASCII valides (jamais issues d'une saisie).
enum WelloLinks {
    /// EULA standard Apple : accepté par App Review, rien à héberger.
    static let conditions = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    /// TODO pré-publication : héberger `docs/legal/privacy-policy.md` et remplacer cette URL.
    static let confidentialité = URL(string: "https://wello.app/confidentialite")!
}

/// Carte de teasing réutilisable (gating contextuel) : invite à passer Wello+.
struct PremiumGateCard: View {
    let bénéfice: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CardContainer {
                HStack(spacing: 14) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(WelloTheme.accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(bénéfice)
                            .font(.welloEntête)
                            .foregroundStyle(WelloTheme.ink)
                        Text("Débloquer avec Wello+")
                            .font(.welloProseDouce)
                            .foregroundStyle(WelloTheme.inkSoft)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WelloTheme.inkSoft.opacity(0.6))
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(bénéfice). Débloquer avec Wello+")
        .accessibilityHint("Ouvre l'offre Wello+")
    }
}

/// Paywall Wello+ : deux offres au choix — abonnement annuel (avec essai gratuit) ou achat à vie.
struct PaywallView: View {
    /// Bénéfice mis en avant selon le point d'entrée.
    var bénéfice: String = "Débloque toutes les fonctionnalités"

    @Environment(EntitlementStore.self) private var entitlements
    @Environment(\.dismiss) private var dismiss

    @State private var produits: [StoreProduct] = []
    @State private var sélection: String?
    @State private var enCours = false
    @State private var messageErreur: String?

    private static let avantages: [(icon: String, titre: String)] = [
        ("clock.arrow.circlepath", "Historique illimité"),
        ("chart.line.uptrend.xyaxis", "Analyses et tendances"),
        ("bell.badge.fill", "Rappels adaptatifs"),
        ("cup.and.saucer.fill", "Boissons personnalisées"),
        ("square.and.arrow.up", "Export CSV de l'historique"),
        ("paintbrush.fill", "Thèmes de couleur"),
    ]

    private var produitSélectionné: StoreProduct? {
        produits.first { $0.id == sélection }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    enTête
                    listeAvantages
                    offres
                    if let messageErreur {
                        Text(messageErreur)
                            .font(.welloProseDouce)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                    boutonAchat
                    boutonRestaurer
                    mentionAbonnement
                    liensLégaux
                }
                .padding()
            }
            .welloBackground()
            .navigationTitle("Wello+")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
            .task {
                produits = await entitlements.produits()
                // Présélection : l'annuel (offre mise en avant), sinon le premier disponible.
                if sélection == nil {
                    sélection = produits.first(where: { $0.kind == .annual })?.id ?? produits.first?.id
                }
            }
        }
    }

    private var enTête: some View {
        VStack(spacing: 8) {
            Image(systemName: "star.fill")
                .font(.system(size: 40))
                .foregroundStyle(WelloTheme.accentGradient)
                .accessibilityHidden(true)
            Text(bénéfice)
                .font(.welloTitre3)
                .foregroundStyle(WelloTheme.ink)
                .multilineTextAlignment(.center)
            Text("Sans engagement, ou une fois pour toutes.")
                .font(.welloProseDouce)
                .foregroundStyle(WelloTheme.inkSoft)
        }
    }

    private var listeAvantages: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Self.avantages, id: \.titre) { a in
                    HStack(spacing: 12) {
                        Image(systemName: a.icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(WelloTheme.accent)
                            .frame(width: 28)
                        Text(a.titre)
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(WelloTheme.ink)
                        Spacer()
                    }
                }
            }
        }
    }

    /// Les deux offres, sélectionnables (radio). Vide tant que StoreKit n'a pas répondu.
    @ViewBuilder private var offres: some View {
        if produits.isEmpty {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 8)
        } else {
            VStack(spacing: 12) {
                ForEach(produits) { carteOffre($0) }
            }
        }
    }

    private func carteOffre(_ p: StoreProduct) -> some View {
        let choisi = sélection == p.id
        return Button {
            sélection = p.id
        } label: {
            HStack(spacing: 14) {
                Image(systemName: choisi ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(choisi ? WelloTheme.accent : WelloTheme.inkSoft.opacity(0.5))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(p.displayName)
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(WelloTheme.ink)
                        if p.kind == .annual {
                            Text("Populaire")
                                .font(.system(.caption2, design: .rounded).weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(WelloTheme.accent.opacity(0.15), in: Capsule())
                                .foregroundStyle(WelloTheme.accentDeep)
                        }
                    }
                    Text(sousTitrePrix(p))
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(WelloTheme.inkSoft)
                }
                Spacer()
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WelloTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(choisi ? WelloTheme.accent : Color.clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(p.displayName), \(sousTitrePrix(p))")
        .accessibilityAddTraits(choisi ? [.isSelected, .isButton] : .isButton)
    }

    /// Ligne de prix sous le nom de l'offre.
    private func sousTitrePrix(_ p: StoreProduct) -> String {
        switch p.kind {
        case .annual:
            if let intro = p.offreIntro { return "\(intro), puis \(p.displayPrice)/an" }
            return "\(p.displayPrice)/an"
        case .lifetime:
            return "\(p.displayPrice) · paiement unique"
        }
    }

    private var boutonAchat: some View {
        Button {
            Task { await acheter() }
        } label: {
            Group {
                if enCours {
                    ProgressView().tint(.white)
                } else {
                    Text(titreBoutonAchat)
                        .font(.system(.headline, design: .rounded))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(WelloTheme.accentGradient,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(enCours || produitSélectionné == nil)
        .accessibilityLabel(titreBoutonAchat)
    }

    /// Libellé du bouton principal selon l'offre choisie.
    private var titreBoutonAchat: String {
        guard let p = produitSélectionné else { return "Débloquer" }
        switch p.kind {
        case .annual:
            return p.offreIntro != nil ? "Commencer l'essai gratuit" : "S'abonner — \(p.displayPrice)/an"
        case .lifetime:
            return "Débloquer — \(p.displayPrice)"
        }
    }

    private var boutonRestaurer: some View {
        Button("Restaurer mes achats") {
            Task { await restaurer() }
        }
        .font(.system(.subheadline, design: .rounded))
        .frame(minHeight: 44)
        .foregroundStyle(WelloTheme.accentDeep)
        .disabled(enCours)
    }

    /// Divulgation d'abonnement auto-renouvelable exigée par l'App Store.
    private var mentionAbonnement: some View {
        Text("L'abonnement annuel se renouvelle automatiquement sauf annulation au moins 24 h avant la fin de la période en cours ; gère-le ou résilie-le dans les réglages de l'App Store. L'option à vie est un paiement unique, sans renouvellement.")
            .font(.welloLégendeMini2)
            .foregroundStyle(WelloTheme.inkSoft)
            .multilineTextAlignment(.center)
    }

    private var liensLégaux: some View {
        HStack(spacing: 18) {
            Link("Conditions d'utilisation", destination: WelloLinks.conditions)
            Link("Confidentialité", destination: WelloLinks.confidentialité)
        }
        .font(.welloLégendeMini)
        .foregroundStyle(WelloTheme.inkSoft)
    }

    private func acheter() async {
        guard let id = sélection else { return }
        enCours = true
        messageErreur = nil
        defer { enCours = false }
        do {
            switch try await entitlements.acheter(id) {
            case .success: dismiss()
            case .userCancelled: break
            case .pending: messageErreur = "Achat en attente de validation."
            }
        } catch {
            messageErreur = "L'achat a échoué. Réessaie plus tard."
        }
    }

    private func restaurer() async {
        enCours = true
        messageErreur = nil
        defer { enCours = false }
        await entitlements.restaurer()
        if entitlements.isUnlocked(.unlimitedHistory) {
            dismiss()
        } else {
            messageErreur = "Aucun achat à restaurer."
        }
    }
}

#if DEBUG
#Preview("Paywall") {
    PaywallView(bénéfice: "Garde tout ton historique")
        .environment(PreviewSupport.entitlements(.free))
}
#endif
