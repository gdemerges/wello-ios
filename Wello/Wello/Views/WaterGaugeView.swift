import SwiftUI

/// Vague sinusoïdale remplissant la forme selon `progress` (0…1), animée via `phase`.
struct WaterWave: Shape {
    var progress: Double
    var phase: Double
    var amplitude: Double = 7

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(progress, phase) }
        set { progress = newValue.first; phase = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let niveau = rect.height * (1 - progress)
        path.move(to: CGPoint(x: 0, y: niveau))
        var x: CGFloat = 0
        while x <= rect.width {
            let relatif = Double(x / max(rect.width, 1))
            let y = niveau + amplitude * sin(relatif * 2 * .pi + phase)
            path.addLine(to: CGPoint(x: x, y: y))
            x += 2
        }
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        path.closeSubpath()
        return path
    }
}

/// Jauge circulaire « verre d'eau » : le niveau monte avec la progression, vague animée.
struct WaterGaugeView: View {
    let consomméML: Int
    let objectifML: Int
    @State private var phase = 0.0

    private var progress: Double {
        guard objectifML > 0 else { return 0 }
        return min(Double(consomméML) / Double(objectifML), 1)
    }
    private var pourcentage: Int { Int((progress * 100).rounded()) }

    var body: some View {
        ZStack {
            Circle().fill(WelloTheme.accent.opacity(0.10))

            WaterWave(progress: progress, phase: phase)
                .fill(WelloTheme.waterGradient)
                .clipShape(Circle())
                .opacity(0.92)

            Circle().strokeBorder(WelloTheme.accent.opacity(0.30), lineWidth: 3)

            VStack(spacing: 2) {
                Text("\(consomméML)")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(WelloTheme.ink)
                    .contentTransition(.numericText())
                Text("/ \(objectifML) ml")
                    .font(.system(.callout, design: .rounded).weight(.medium))
                    .foregroundStyle(WelloTheme.inkSoft)
                Text("\(pourcentage) %")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(WelloTheme.accentDeep)
                    .padding(.top, 2)
            }
        }
        .frame(width: 250, height: 250)
        .onAppear {
            withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
        .animation(.easeInOut(duration: 0.7), value: progress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hydratation du jour")
        .accessibilityValue("\(consomméML) millilitres sur \(objectifML), \(pourcentage) pour cent")
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
