import SwiftUI
import WelloKit

/// Teintes minimales (dupliquées pour découpler la Watch du thème app, comme le widget).
private enum WatchTheme {
    static let accent = Color(red: 0.31, green: 0.69, blue: 0.90)
    static let accentDeep = Color(red: 0.18, green: 0.55, blue: 0.79)
    static let gradient = LinearGradient(colors: [accent, accentDeep],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// Anneau de progression (repris du widget).
private struct Ring: View {
    let fraction: Double
    var body: some View {
        ZStack {
            Circle().stroke(WatchTheme.accent.opacity(0.18), lineWidth: 9)
            Circle()
                .trim(from: 0, to: max(0.001, fraction))
                .stroke(WatchTheme.gradient, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

/// Écran principal de l'app Watch : jauge + 3 boutons d'ajout rapide + annuler.
struct WatchMainView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        ScrollView {
            if store.configuré {
                VStack(spacing: 10) {
                    ZStack {
                        Ring(fraction: store.progress.fraction)
                        VStack(spacing: 1) {
                            Text(store.progress.libelléPourcent)
                                .font(.system(.title3, design: .rounded).weight(.bold))
                                .foregroundStyle(WatchTheme.accentDeep)
                            Text(store.progress.libelléValeurs)
                                .font(.system(.caption2, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(height: 92)

                    HStack(spacing: 6) {
                        ForEach(store.quickAdds, id: \.self) { ml in
                            Button { store.ajouter(ml: ml) } label: {
                                Text("+\(ml)")
                                    .font(.system(.footnote, design: .rounded).weight(.bold))
                                    .frame(maxWidth: .infinity)
                            }
                            .tint(WatchTheme.accent)
                        }
                    }

                    Button("Annuler", systemImage: "arrow.uturn.backward") {
                        store.annulerDernière()
                    }
                    .font(.caption2)
                    .tint(.secondary)
                }
                .padding(.horizontal, 4)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "drop").font(.title).foregroundStyle(WatchTheme.accent)
                    Text("Ouvre Wello sur l'iPhone")
                        .font(.footnote).multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
        }
        .navigationTitle("Wello")
        .task { await store.démarrer() }
    }
}
