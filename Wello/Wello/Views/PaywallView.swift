import SwiftUI
import WelloKit

/// Liens légaux requis par l'App Store pour un achat. À remplacer par les vraies URLs.
/// Force-unwrap sûr : ce sont des constantes ASCII valides (jamais issues d'une saisie).
enum WelloLinks {
    static let conditions = URL(string: "https://wello.app/conditions")!
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
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(WelloTheme.ink)
                        Text("Débloquer avec Wello+")
                            .font(.system(.subheadline, design: .rounded))
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

/// Paywall Wello+ : achat unique « lifetime ».
struct PaywallView: View {
    /// Bénéfice mis en avant selon le point d'entrée.
    var bénéfice: String = "Débloque toutes les fonctionnalités"

    @Environment(EntitlementStore.self) private var entitlements
    @Environment(\.dismiss) private var dismiss

    @State private var produit: StoreProduct?
    @State private var enCours = false
    @State private var messageErreur: String?

    private static let avantages: [(icon: String, titre: String)] = [
        ("clock.arrow.circlepath", "Historique illimité"),
        ("chart.line.uptrend.xyaxis", "Analyses et tendances"),
        ("cup.and.saucer.fill", "Boissons personnalisées"),
        ("square.and.arrow.up", "Export CSV / PDF"),
        ("paintbrush.fill", "Thèmes de couleur"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    enTête
                    listeAvantages
                    if let messageErreur {
                        Text(messageErreur)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                    boutonAchat
                    boutonRestaurer
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
            .task { produit = await entitlements.produit() }
        }
    }

    private var enTête: some View {
        VStack(spacing: 8) {
            Image(systemName: "star.fill")
                .font(.system(size: 40))
                .foregroundStyle(WelloTheme.accentGradient)
                .accessibilityHidden(true)
            Text(bénéfice)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(WelloTheme.ink)
                .multilineTextAlignment(.center)
            Text("Un seul paiement, à vie.")
                .font(.system(.subheadline, design: .rounded))
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

    private var boutonAchat: some View {
        Button {
            Task { await acheter() }
        } label: {
            Group {
                if enCours {
                    ProgressView().tint(.white)
                } else {
                    Text(produit.map { "Débloquer — \($0.displayPrice)" } ?? "Débloquer")
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
        .disabled(enCours)
        .accessibilityLabel(produit.map { "Débloquer Wello+ pour \($0.displayPrice)" } ?? "Débloquer Wello+")
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

    private var liensLégaux: some View {
        HStack(spacing: 18) {
            Link("Conditions d'utilisation", destination: WelloLinks.conditions)
            Link("Confidentialité", destination: WelloLinks.confidentialité)
        }
        .font(.system(.caption, design: .rounded))
        .foregroundStyle(WelloTheme.inkSoft)
    }

    private func acheter() async {
        enCours = true
        messageErreur = nil
        defer { enCours = false }
        do {
            switch try await entitlements.acheterPlus() {
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
