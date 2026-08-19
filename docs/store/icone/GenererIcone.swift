// Génère l'icône App Store de Wello en 1024×1024 (Core Graphics, aucune dépendance).
//
//     swift docs/store/icone/GenererIcone.swift docs/store/icone
//
// Pourquoi un script et pas un fichier de design : l'icône doit pouvoir être re-rendue à
// l'identique dans les 4 teintes de thème (Wello+) à partir de la MÊME palette que l'app
// (`WelloKit/Models/AppTheme.swift`). Un export manuel dérive ; ce script, non.
//
// Parti pris visuel — l'icône v1 (goutte blanche sur dégradé bleu clair) était le cliché exact
// de la catégorie : indistinguable de dizaines de concurrents dans une grille de résultats.
// Ici : fond bleu nuit profond (personne ne le fait dans cette catégorie), et la goutte n'est
// pas pleine mais **remplie à un niveau**, avec une crête d'onde. C'est la signature réelle de
// l'app — la jauge liquide — et ça dit « suivi », pas seulement « eau ».

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Palette (miroir de WelloKit/Models/AppTheme.swift)

struct Palette {
    let nom: String
    let accent: UInt32
    let accentDeep: UInt32
    let waterTop: UInt32
    let waterBottom: UInt32
    /// Fond sombre, décliné sur la teinte du thème.
    let fondHaut: UInt32
    let fondBas: UInt32
}

let palettes = [
    Palette(nom: "AppIcon", accent: 0x4FB0E5, accentDeep: 0x2E8BC9,
            waterTop: 0x86D7F5, waterBottom: 0x3FA3E0, fondHaut: 0x102C46, fondBas: 0x081726),
    Palette(nom: "AppIcon-Aurore", accent: 0xFF8FA3, accentDeep: 0xE85D75,
            waterTop: 0xFFB3C1, waterBottom: 0xF87890, fondHaut: 0x3D1622, fondBas: 0x220A11),
    Palette(nom: "AppIcon-Menthe", accent: 0x4FD0A8, accentDeep: 0x2EA888,
            waterTop: 0x86F5D7, waterBottom: 0x3FE0B0, fondHaut: 0x0E3630, fondBas: 0x061E1A),
    Palette(nom: "AppIcon-Crepuscule", accent: 0x8B7FE5, accentDeep: 0x6B5DC9,
            waterTop: 0xB3A8F5, waterBottom: 0x8878E0, fondHaut: 0x241E45, fondBas: 0x120F26),
]

func couleur(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}

// MARK: - Géométrie

let taille: CGFloat = 1024

/// Goutte classique : un cercle, et deux tangentes qui montent vers l'apex.
/// Les points de tangence sont calculés (pas placés à l'œil) pour que le raccord soit lisse.
func cheminGoutte() -> CGPath {
    let apex = CGPoint(x: 512, y: 122)
    let centre = CGPoint(x: 512, y: 672)
    let rayon: CGFloat = 246

    // Points de tangence exacts entre l'apex et le cercle : c'est ce qui garantit un raccord
    // sans cassure visible entre les flancs et la panse.
    let d = centre.y - apex.y
    let angle = acos(rayon / d)
    let dx = rayon * sin(angle)
    let dy = rayon * cos(angle)
    let tGauche = CGPoint(x: centre.x - dx, y: centre.y - dy)
    let tDroite = CGPoint(x: centre.x + dx, y: centre.y - dy)

    let chemin = CGMutablePath()
    chemin.move(to: apex)
    chemin.addLine(to: tDroite)   // tangente exacte : raccord sans cassure sur l'épaule
    let départ = atan2(tDroite.y - centre.y, tDroite.x - centre.x)
    let fin = atan2(tGauche.y - centre.y, tGauche.x - centre.x)
    chemin.addArc(center: centre, radius: rayon, startAngle: départ, endAngle: fin, clockwise: false)
    chemin.addLine(to: apex)
    chemin.closeSubpath()
    return chemin
}

/// Surface d'eau : rectangle jusqu'en bas, coiffé d'une sinusoïde. `niveau` = y de la surface.
func cheminEau(niveau: CGFloat, amplitude: CGFloat, phase: CGFloat) -> CGPath {
    let chemin = CGMutablePath()
    chemin.move(to: CGPoint(x: 0, y: niveau))
    var x: CGFloat = 0
    while x <= taille {
        let y = niveau + sin(x / taille * .pi * 4 + phase) * amplitude
        chemin.addLine(to: CGPoint(x: x, y: y))
        x += 4
    }
    chemin.addLine(to: CGPoint(x: taille, y: taille))
    chemin.addLine(to: CGPoint(x: 0, y: taille))
    chemin.closeSubpath()
    return chemin
}

// MARK: - Rendu

func rendre(_ p: Palette, vers dossier: URL) throws {
    let espace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: Int(taille), height: Int(taille),
                              bitsPerComponent: 8, bytesPerRow: 0, space: espace,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
        throw NSError(domain: "icone", code: 1)
    }
    // Repère en y-vers-le-bas : toute la géométrie ci-dessus se lit comme une maquette.
    ctx.translateBy(x: 0, y: taille)
    ctx.scaleBy(x: 1, y: -1)
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    // 1. Fond : dégradé sombre. Aucune icône d'hydratation du Store n'est sombre — c'est
    //    précisément ce qui rend celle-ci repérable dans une grille.
    let fond = CGGradient(colorsSpace: espace,
                          colors: [couleur(p.fondHaut), couleur(p.fondBas)] as CFArray,
                          locations: [0, 1])!
    ctx.drawLinearGradient(fond, start: .zero, end: CGPoint(x: taille * 0.35, y: taille),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

    // 2. Halo derrière la goutte : donne la profondeur, évite le rendu « sticker plat ».
    let halo = CGGradient(colorsSpace: espace,
                          colors: [couleur(p.accent, 0.30), couleur(p.accent, 0)] as CFArray,
                          locations: [0, 1])!
    ctx.drawRadialGradient(halo, startCenter: CGPoint(x: 512, y: 600), startRadius: 40,
                           endCenter: CGPoint(x: 512, y: 600), endRadius: 470, options: [])

    let goutte = cheminGoutte()

    // 3. Corps de la goutte : le « verre » vide, translucide et à peine teinté.
    ctx.saveGState()
    ctx.addPath(goutte)
    ctx.setFillColor(couleur(0xFFFFFF, 0.10))
    ctx.fillPath()
    ctx.restoreGState()

    // 4. L'eau, découpée par la goutte : c'est LE signe distinctif — un niveau, pas un remplissage.
    //    ~62 % : assez plein pour lire « eau », assez vide pour lire « il en reste à boire ».
    ctx.saveGState()
    ctx.addPath(goutte)
    ctx.clip()
    let niveau: CGFloat = 122 + (918 - 122) * 0.40
    ctx.addPath(cheminEau(niveau: niveau, amplitude: 26, phase: 0.9))
    ctx.clip()
    // Le bas doit vraiment plonger : un aplat clair uniforme fait « autocollant ».
    let eau = CGGradient(colorsSpace: espace,
                         colors: [couleur(p.waterTop), couleur(p.accent),
                                  couleur(p.accentDeep), couleur(p.accentDeep, 1)] as CFArray,
                         locations: [0, 0.28, 0.72, 1])!
    ctx.drawLinearGradient(eau, start: CGPoint(x: 0, y: niveau - 30),
                           end: CGPoint(x: 0, y: 918),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()

    // 4bis. Ombre douce juste sous la surface : sans elle, plein et vide se touchent sans
    //       transition et l'ensemble paraît découpé aux ciseaux.
    ctx.saveGState()
    ctx.addPath(goutte)
    ctx.clip()
    let ombre = CGGradient(colorsSpace: espace,
                           colors: [couleur(0x000000, 0.22), couleur(0x000000, 0)] as CFArray,
                           locations: [0, 1])!
    ctx.drawLinearGradient(ombre, start: CGPoint(x: 0, y: niveau - 20),
                           end: CGPoint(x: 0, y: niveau + 120), options: [])
    ctx.restoreGState()

    // 5. Crête de l'onde : un liseré clair sur la surface, sinon la ligne d'eau paraît « collée ».
    ctx.saveGState()
    ctx.addPath(goutte)
    ctx.clip()
    let crête = CGMutablePath()
    var x: CGFloat = 0
    crête.move(to: CGPoint(x: 0, y: niveau))
    while x <= taille {
        crête.addLine(to: CGPoint(x: x, y: niveau + sin(x / taille * .pi * 4 + 0.9) * 26))
        x += 4
    }
    ctx.addPath(crête)
    ctx.setStrokeColor(couleur(0xFFFFFF, 0.55))
    ctx.setLineWidth(7)
    ctx.setLineCap(.round)
    ctx.strokePath()
    ctx.restoreGState()

    // 6. Contour de la goutte : clair en haut (partie vide, elle doit rester lisible sur le
    //    fond sombre), et une fine reprise interne pour l'effet « verre ».
    ctx.saveGState()
    ctx.addPath(goutte)
    ctx.setStrokeColor(couleur(0xFFFFFF, 0.62))
    ctx.setLineWidth(6)
    ctx.strokePath()
    ctx.restoreGState()

    // 7. Reflet : une ellipse douce sur l'épaule gauche, comme sur du verre.
    ctx.saveGState()
    ctx.addPath(goutte)
    ctx.clip()
    ctx.setFillColor(couleur(0xFFFFFF, 0.16))
    ctx.fillEllipse(in: CGRect(x: 372, y: 300, width: 84, height: 190))
    ctx.setFillColor(couleur(0xFFFFFF, 0.12))
    ctx.fillEllipse(in: CGRect(x: 342, y: 580, width: 58, height: 104))
    ctx.restoreGState()

    guard let image = ctx.makeImage() else { throw NSError(domain: "icone", code: 2) }
    let url = dossier.appendingPathComponent("\(p.nom).png")
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "icone", code: 3)
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { throw NSError(domain: "icone", code: 4) }
    print("✓ \(url.path)")
}

let dossier = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
for p in palettes { try rendre(p, vers: dossier) }
