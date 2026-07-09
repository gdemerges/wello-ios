import SwiftUI
import UIKit
import WelloKit

// MARK: - Couleurs

extension Color {
    /// Initialise une couleur depuis un hex 0xRRGGBB.
    init(hex: UInt, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }

    /// Couleur adaptative clair/sombre.
    static func adaptive(light: UInt, dark: UInt) -> Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

// MARK: - Thème

/// Palette et styles « eau / hydratation » de Wello.
/// Les 4 teintes d'accent sont thématisables (Wello+) : elles se lisent sur `current`, palette
/// active mutée par `ThemeStore`. Les neutres adaptatifs restent fixes (lisibilité clair/sombre).
enum WelloTheme {
    /// Thème actif. Posé par `ThemeStore` au démarrage (défaut `glacier` = palette historique).
    static var current: AppTheme = .glacier

    static var accent: Color { Color(hex: current.palette.accent) }          // bleu glacier (défaut)
    static var accentDeep: Color { Color(hex: current.palette.accentDeep) }
    static var waterTop: Color { Color(hex: current.palette.waterTop) }
    static var waterBottom: Color { Color(hex: current.palette.waterBottom) }

    static let canvas = Color.adaptive(light: 0xF2F9FF, dark: 0x0A141F)
    static let card = Color.adaptive(light: 0xFFFFFF, dark: 0x132231)
    static let ink = Color.adaptive(light: 0x0B2A4A, dark: 0xEAF6FF)
    static let inkSoft = Color.adaptive(light: 0x5B7790, dark: 0x9DB6CC)

    static var waterGradient: LinearGradient {
        LinearGradient(colors: [waterTop, waterBottom], startPoint: .top, endPoint: .bottom)
    }
    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accent, accentDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Fond d'écran

/// Fond standard : voile clair avec un léger halo bleu en haut.
struct WelloBackground: ViewModifier {
    func body(content: Content) -> some View {
        content.background(
            ZStack {
                WelloTheme.canvas
                LinearGradient(colors: [WelloTheme.accent.opacity(0.14), .clear],
                               startPoint: .top, endPoint: .center)
            }
            .ignoresSafeArea()
        )
    }
}

extension View {
    func welloBackground() -> some View { modifier(WelloBackground()) }
}

// MARK: - Composants réutilisables

/// Bouton d'ajout d'eau : pilule en dégradé clair qui se compresse et s'assombrit
/// brièvement à chaque tap. La pulsation est déclenchée par l'action (et non par
/// `isPressed`) pour rester visible même sur un clic instantané (simulateur).
struct WaterLogButton: View {
    let ml: Int
    let action: () async -> Void
    @State private var enfoncé = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.13, dampingFraction: 0.5)) { enfoncé = true }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(130))
                withAnimation(.spring(response: 0.34, dampingFraction: 0.62)) { enfoncé = false }
            }
            Task { await action() }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "drop.fill").font(.system(size: 15))
                Text("+\(ml)").font(.system(.headline, design: .rounded)).minimumScaleFactor(0.7).lineLimit(1)
            }
            .foregroundStyle(WelloTheme.accentDeep)          // teinte accent, plus la jauge qui porte la saturation
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(WelloTheme.accent.opacity(enfoncé ? 0.24 : 0.14),   // fond teinté doux, plus foncé au tap
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .scaleEffect(enfoncé && !reduceMotion ? 0.92 : 1) // pas de scale si Reduce Motion
            .shadow(color: .black.opacity(0.05), radius: 4, y: 2)  // affordance discrète (plus de halo saturé)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ajouter \(ml) millilitres")
    }
}

/// Pastille « Autre » (contour) assortie aux WaterLogButton : ouvre la saisie ponctuelle.
struct WaterMorePill: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: "slider.horizontal.3").font(.system(size: 15))
                Text("Autre").font(.system(.headline, design: .rounded))
            }
            .foregroundStyle(WelloTheme.accentDeep)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(WelloTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(WelloTheme.accent.opacity(0.35), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ajouter une autre quantité")
    }
}

/// Logo-texte « Wello » : goutte + mot rempli du dégradé eau, police arrondie lourde.
struct WelloWordmark: View {
    /// Taille suivant Dynamic Type (relative à Title 3).
    @ScaledMetric(relativeTo: .title3) private var size: CGFloat = 22
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "drop.fill")
                .font(.system(size: size * 0.78, weight: .bold))
            Text("Wello")
                .font(.system(size: size, weight: .heavy, design: .rounded))
                .tracking(0.5)
        }
        .foregroundStyle(WelloTheme.accentGradient)
        .accessibilityElement()
        .accessibilityLabel("Wello")
        .accessibilityAddTraits(.isHeader)
    }
}

/// Carte arrondie douce sur fond `card`.
struct CardContainer<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WelloTheme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 14, y: 6)
    }
}
