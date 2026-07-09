import SwiftUI

/// Système typographique de Wello — **deux voix délibérées** :
///
/// • **Éditorial** — New York (serif système) : titres d'écran, en-têtes de carte, titres de
///   composantes. Donne une gravité « premium/soin » et casse la monotonie de l'arrondi.
/// • **Prose** — SF Pro (par défaut) : paragraphes explicatifs, sous-titres, sources, footers.
///   Plus lisible en texte long que l'arrondi.
///
/// La troisième voix, **données/UI**, reste en **SF Rounded** (chiffres du compteur, valeurs,
/// boutons, chips, wordmark, jauge) : c'est l'identité « eau » de la marque, à ne pas toucher.
///
/// Règle mnémotechnique : **serif = ce qu'on lit, arrondi = ce qu'on manipule ou mesure.**
/// Le serif s'emploie avec parcimonie (les vrais titres uniquement), pas sur chaque texte gras.
extension Font {
    // MARK: Éditorial — New York (serif système)

    /// Grand titre d'écran (onboarding).
    static let welloTitreÉcran = Font.system(.title, design: .serif).weight(.semibold)
    /// Gros titre (feuille de détail d'une composante).
    static let welloTitre = Font.system(.title2, design: .serif).weight(.semibold)
    /// Titre moyen (en-tête de paywall, grande valeur mise en scène).
    static let welloTitre3 = Font.system(.title3, design: .serif).weight(.semibold)
    /// En-tête de carte / heading de section de contenu.
    static let welloEntête = Font.system(.headline, design: .serif).weight(.semibold)

    // MARK: Prose — SF Pro (par défaut)

    /// Paragraphe explicatif.
    static let welloProse = Font.system(.body)
    /// Prose secondaire : sous-titre sous un en-tête, chapeau d'intro.
    static let welloProseDouce = Font.system(.subheadline)
    /// Source / note de bas.
    static let welloLégende = Font.system(.footnote)
    /// Légende, footer de section.
    static let welloLégendeMini = Font.system(.caption)
    /// Mention fine (divulgation légale).
    static let welloLégendeMini2 = Font.system(.caption2)
}
