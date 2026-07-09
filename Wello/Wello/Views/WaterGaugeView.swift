import SwiftUI

/// Vague sinusoïdale remplissant la forme selon `progress` (0…1). `phase` (piloté image par
/// image par un `TimelineView`) décale la crête ; `frequency` = nombre de crêtes sur la largeur
/// (permet de superposer deux ondes décorrélées).
///
/// Seul `progress` est *animable* (montée « ressort » du niveau) : `phase` est recalculé à
/// chaque image et ne doit donc pas s'interpoler, sinon les deux mouvements se marchent dessus.
struct WaterWave: Shape {
    var progress: Double
    var phase: Double
    var amplitude: Double = 7
    var frequency: Double = 1

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let niveau = rect.height * (1 - progress)
        path.move(to: CGPoint(x: 0, y: niveau))
        var x: CGFloat = 0
        while x <= rect.width {
            let relatif = Double(x / max(rect.width, 1))
            let y = niveau + amplitude * sin(relatif * 2 * .pi * frequency + phase)
            path.addLine(to: CGPoint(x: x, y: y))
            x += 2
        }
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        path.closeSubpath()
        return path
    }
}

/// Jauge circulaire « verre d'eau » : le niveau monte avec la progression. Deux vagues
/// superposées + ligne de surface (ménisque) donnent le mouvement d'un liquide ; un rim
/// éclairé en haut simule le verre, et une lentille givrée au centre garantit la lisibilité
/// du compteur quelle que soit la hauteur d'eau derrière lui.
struct WaterGaugeView: View {
    let consomméML: Int
    let objectifML: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Taille du compteur suivant Dynamic Type (bornée par minimumScaleFactor côté affichage).
    @ScaledMetric(relativeTo: .largeTitle) private var tailleNombre: CGFloat = 52
    /// Période d'un cycle complet de la vague (secondes).
    private let période = 2.4

    private var progress: Double {
        guard objectifML > 0 else { return 0 }
        return min(Double(consomméML) / Double(objectifML), 1)
    }
    private var pourcentage: Int { Int((progress * 100).rounded()) }

    /// Rim de verre : liseré clair en haut fondu vers l'accent en bas → volume.
    private var rimGradient: LinearGradient {
        LinearGradient(colors: [.white.opacity(0.55), WelloTheme.accent.opacity(0.22)],
                       startPoint: .top, endPoint: .bottom)
    }

    var body: some View {
        // Vague figée (mais toujours dessinée) si Reduce Motion est actif.
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let phase = reduceMotion ? 0 : (t.truncatingRemainder(dividingBy: période) / période) * 2 * .pi
            contenu(phase: phase)
        }
        .frame(width: 250, height: 250)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hydratation du jour")
        .accessibilityValue("\(consomméML) millilitres sur \(objectifML), \(pourcentage) pour cent")
    }

    private func contenu(phase: Double) -> some View {
        ZStack {
            // Puits vide, légèrement teinté.
            Circle().fill(WelloTheme.accent.opacity(0.08))

            // Eau : vague arrière décorrélée + vague avant + ménisque de surface, clippées au cercle.
            ZStack {
                WaterWave(progress: progress, phase: phase * 0.8 + .pi, amplitude: 5, frequency: 1.6)
                    .fill(WelloTheme.waterGradient)
                    .opacity(0.5)
                WaterWave(progress: progress, phase: phase, amplitude: 8)
                    .fill(WelloTheme.waterGradient)
                    .opacity(0.95)
                WaterWave(progress: progress, phase: phase, amplitude: 8)
                    .stroke(.white.opacity(0.45), lineWidth: 1.5)   // ménisque : reflet à la surface
            }
            .clipShape(Circle())

            // Verre : rim éclairé en haut.
            Circle().strokeBorder(rimGradient, lineWidth: 2.5)

            // Lentille de lecture givrée : contraste garanti sur l'eau à tout niveau de remplissage.
            VStack(spacing: 2) {
                Text("\(consomméML)")
                    .font(.system(size: tailleNombre, weight: .bold, design: .rounded))
                    .foregroundStyle(WelloTheme.ink)
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("/ \(objectifML) ml")
                    .font(.system(.callout, design: .rounded).weight(.medium))
                    .foregroundStyle(WelloTheme.inkSoft)
                Text("\(pourcentage) %")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(WelloTheme.accentDeep)
                    .padding(.top, 2)
            }
            .padding(24)
            .frame(width: 150, height: 150)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1))
            .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
        }
        // Montée « ressort » du niveau d'eau à chaque ajout ; instantanée si Reduce Motion.
        .animation(reduceMotion ? nil : .spring(response: 0.8, dampingFraction: 0.82), value: progress)
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 40) {
        WaterGaugeView(consomméML: 1250, objectifML: 2730)
        WaterGaugeView(consomméML: 2730, objectifML: 2730)
    }
    .padding()
    .welloBackground()
}
#endif
