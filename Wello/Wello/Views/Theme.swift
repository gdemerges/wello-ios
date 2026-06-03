import SwiftUI
import UIKit

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
enum WelloTheme {
    static let accent = Color(hex: 0x4FB0E5)        // bleu glacier
    static let accentDeep = Color(hex: 0x2E8BC9)
    static let waterTop = Color(hex: 0x86D7F5)
    static let waterBottom = Color(hex: 0x3FA3E0)

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
                Text("+\(ml)").font(.system(.headline, design: .rounded))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(WelloTheme.waterGradient,            // plus clair au repos
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .brightness(enfoncé ? -0.14 : 0)                 // s'assombrit le temps de la pulsation
            .scaleEffect(enfoncé ? 0.92 : 1)
            .shadow(color: WelloTheme.accent.opacity(0.35), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }
}

/// Logo-texte « Wello » : goutte + mot rempli du dégradé eau, police arrondie lourde.
struct WelloWordmark: View {
    var size: CGFloat = 22
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
