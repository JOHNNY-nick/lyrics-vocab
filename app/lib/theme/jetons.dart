// Jetons de la charte graphique (43.2 à 43.4, 43.11). Aucun écran n'utilise de valeur visuelle
// écrite en dur (DES-02) : tout passe par ce fichier.
import 'package:flutter/material.dart';

/// Couleurs nommées (43.2), avec leur variante sombre (43.11).
@immutable
class Couleurs extends ThemeExtension<Couleurs> {
  const Couleurs({
    required this.violet,
    required this.violetFonce,
    required this.rose,
    required this.jaune,
    required this.turquoise,
    required this.encre,
    required this.fond,
    required this.surface,
    required this.lavande,
    required this.bordure,
    required this.texteSecondaire,
    required this.navInactif,
    required this.vertTexte,
    required this.orange,
    required this.surAccent,
    required this.surViolet,
    required this.nouveauFond,
    required this.nouveauTexte,
    required this.enCoursFond,
    required this.enCoursTexte,
    required this.acquisFond,
    required this.acquisTexte,
    required this.erreurTexte,
    required this.ombre,
  });

  final Color violet;
  final Color violetFonce;
  final Color rose;
  final Color jaune;
  final Color turquoise;
  final Color encre;
  final Color fond;
  final Color surface;
  final Color lavande;
  final Color bordure;
  final Color texteSecondaire;
  final Color navInactif;
  final Color vertTexte;
  final Color orange;

  /// Texte posé sur rose, jaune ou turquoise : toujours foncé (#1B1740).
  final Color surAccent;

  /// Texte posé sur violet : blanc.
  final Color surViolet;
  final Color nouveauFond;
  final Color nouveauTexte;
  final Color enCoursFond;
  final Color enCoursTexte;
  final Color acquisFond;
  final Color acquisTexte;
  final Color erreurTexte;

  /// Couleur de base des ombres (encre).
  final Color ombre;

  static const clair = Couleurs(
    violet: Color(0xFF6C4DFF),
    violetFonce: Color(0xFF4B2FD6),
    rose: Color(0xFFFF5C8A),
    jaune: Color(0xFFFFC93C),
    turquoise: Color(0xFF19C3B1),
    encre: Color(0xFF1B1740),
    fond: Color(0xFFF6F4FF),
    surface: Color(0xFFFFFFFF),
    lavande: Color(0xFFEAE5FF),
    bordure: Color(0xFFE3DEFA),
    texteSecondaire: Color(0xFF5A5680),
    navInactif: Color(0xFF6B6791),
    vertTexte: Color(0xFF0B2B28),
    orange: Color(0xFFFF8A4C),
    surAccent: Color(0xFF1B1740),
    surViolet: Color(0xFFFFFFFF),
    nouveauFond: Color(0xFFFFE9A8),
    nouveauTexte: Color(0xFF1B1740),
    enCoursFond: Color(0xFFFFD3E0),
    enCoursTexte: Color(0xFF7A1239),
    acquisFond: Color(0xFFBFF1EA),
    acquisTexte: Color(0xFF0B2B28),
    erreurTexte: Color(0xFF7A1239),
    ombre: Color(0xFF1B1740),
  );

  /// Thème sombre proposé (43.11) : seules les couleurs neutres changent.
  static const sombre = Couleurs(
    violet: Color(0xFF6C4DFF),
    violetFonce: Color(0xFFB8A9FF),
    rose: Color(0xFFFF5C8A),
    jaune: Color(0xFFFFC93C),
    turquoise: Color(0xFF19C3B1),
    encre: Color(0xFFF6F4FF),
    fond: Color(0xFF14112E),
    surface: Color(0xFF1F1B45),
    lavande: Color(0xFF2B2561),
    bordure: Color(0xFF3A3470),
    texteSecondaire: Color(0xFFB8B3E0),
    navInactif: Color(0xFF9B96C8),
    vertTexte: Color(0xFF0B2B28),
    orange: Color(0xFFFF8A4C),
    surAccent: Color(0xFF1B1740),
    surViolet: Color(0xFFFFFFFF),
    nouveauFond: Color(0xFFFFE9A8),
    nouveauTexte: Color(0xFF1B1740),
    enCoursFond: Color(0xFFFFD3E0),
    enCoursTexte: Color(0xFF7A1239),
    acquisFond: Color(0xFFBFF1EA),
    acquisTexte: Color(0xFF0B2B28),
    erreurTexte: Color(0xFF7A1239),
    ombre: Color(0xFF000000),
  );

  /// Couleurs d'avatar attribuées en boucle (43.2).
  List<Color> get avatars => [violet, rose, turquoise, jaune, orange, violetFonce];

  /// Texte lisible sur une couleur d'avatar : blanc sur violet et violet foncé, encre sinon.
  Color texteSurAvatar(Color fondAvatar) =>
      (fondAvatar == violet || fondAvatar == Couleurs.clair.violetFonce) ? surViolet : surAccent;

  @override
  Couleurs copyWith() => this;

  @override
  Couleurs lerp(ThemeExtension<Couleurs>? other, double t) => this;
}

/// Polices embarquées (DES-07).
class Polices {
  static const titre = 'Bricolage Grotesque';
  static const corps = 'Plus Jakarta Sans';
}

/// Styles de texte (43.3). La couleur est appliquée par le thème ou par le composant.
class Textes {
  // Interligne naturel de la police (titres sans line-height dans les planches, DES-33).
  static const titreEcran = TextStyle(fontFamily: Polices.titre, fontWeight: FontWeight.w800, fontSize: 34);

  /// Titre de l'écran des artistes (line-height 1,1 dans la planche).
  static const titreEcranSerre = TextStyle(
    fontFamily: Polices.titre,
    fontWeight: FontWeight.w800,
    fontSize: 34,
    height: 1.1,
  );
  static const titreMot = TextStyle(fontFamily: Polices.titre, fontWeight: FontWeight.w800, fontSize: 52);
  static const titreExtrait = TextStyle(
    fontFamily: Polices.titre,
    fontWeight: FontWeight.w800,
    fontSize: 28,
    height: 1.25,
  );
  static const titreCarte = TextStyle(
    fontFamily: Polices.titre,
    fontWeight: FontWeight.w800,
    fontSize: 26,
    height: 1.2,
  );
  static const termeListe = TextStyle(
    fontFamily: Polices.titre,
    fontWeight: FontWeight.w800,
    fontSize: 20,
    height: 1.2,
  );
  static const valeur = TextStyle(
    fontFamily: Polices.titre,
    fontWeight: FontWeight.w800,
    fontSize: 22,
    height: 1.2,
  );
  static const initiales = TextStyle(
    fontFamily: Polices.titre,
    fontWeight: FontWeight.w800,
    fontSize: 30,
    height: 1.0,
  );
  static const extraitFiche = TextStyle(
    fontFamily: Polices.corps,
    fontWeight: FontWeight.w700,
    fontSize: 18,
    height: 1.45,
  );
  static const corps = TextStyle(
    fontFamily: Polices.corps,
    fontWeight: FontWeight.w500,
    fontSize: 15,
    height: 1.45,
  );
  static const corpsExplication = TextStyle(
    fontFamily: Polices.corps,
    fontWeight: FontWeight.w500,
    fontSize: 15,
    height: 1.5,
  );
  static const corpsListe = TextStyle(
    fontFamily: Polices.corps,
    fontWeight: FontWeight.w500,
    fontSize: 14,
    height: 1.3,
  );
  static const saisie = TextStyle(
    fontFamily: Polices.corps,
    fontWeight: FontWeight.w500,
    fontSize: 17,
    height: 1.3,
  );
  static const bouton = TextStyle(
    fontFamily: Polices.corps,
    fontWeight: FontWeight.w700,
    fontSize: 16,
    height: 1.2,
  );
  static const boutonContinuer = TextStyle(
    fontFamily: Polices.corps,
    fontWeight: FontWeight.w700,
    fontSize: 17,
    height: 1.2,
  );
  static const lien = TextStyle(
    fontFamily: Polices.corps,
    fontWeight: FontWeight.w700,
    fontSize: 14,
    height: 1.2,
  );
  static const etiquette = TextStyle(
    fontFamily: Polices.corps,
    fontWeight: FontWeight.w700,
    fontSize: 13,
    height: 1.2,
  );
  static const etiquetteMajuscules = TextStyle(
    fontFamily: Polices.corps,
    fontWeight: FontWeight.w700,
    fontSize: 13,
    height: 1.2,
    letterSpacing: 13 * 0.04,
  );
  static const libelleCarte = TextStyle(
    fontFamily: Polices.corps,
    fontWeight: FontWeight.w700,
    fontSize: 12,
    height: 1.2,
  );
  static const legendeTuile = TextStyle(
    fontFamily: Polices.corps,
    fontWeight: FontWeight.w600,
    fontSize: 12,
    height: 1.2,
  );
  static const pastilleNiveau = TextStyle(
    fontFamily: Polices.corps,
    fontWeight: FontWeight.w700,
    fontSize: 12,
    height: 1.2,
  );
  static const etiquetteIA = TextStyle(
    fontFamily: Polices.corps,
    fontWeight: FontWeight.w700,
    fontSize: 11,
    height: 1.2,
  );
  static const legende = TextStyle(
    fontFamily: Polices.corps,
    fontWeight: FontWeight.w500,
    fontSize: 13,
    height: 1.3,
  );
  static const navigation = TextStyle(
    fontFamily: Polices.corps,
    fontWeight: FontWeight.w700,
    fontSize: 12,
    height: 1.2,
  );
  static const date = TextStyle(
    fontFamily: Polices.corps,
    fontWeight: FontWeight.w700,
    fontSize: 14,
    height: 1.2,
  );
  static const reglage = TextStyle(
    fontFamily: Polices.corps,
    fontWeight: FontWeight.w700,
    fontSize: 15,
    height: 1.3,
  );
  static const logo = TextStyle(
    fontFamily: Polices.titre,
    fontWeight: FontWeight.w800,
    fontSize: 20,
    height: 1.1,
  );
}

/// Espacements (grille de 2, 43.4).
class Espaces {
  static const double e2 = 2;
  static const double e3 = 3;
  static const double e4 = 4;
  static const double e6 = 6;
  static const double e8 = 8;
  static const double e9 = 9;
  static const double e10 = 10;
  static const double e12 = 12;
  static const double e14 = 14;
  static const double e16 = 16;
  static const double e18 = 18;
  static const double e20 = 20;
  static const double e22 = 22;
  static const double e24 = 24;
  static const double e32 = 32;

  /// Marge latérale des écrans.
  static const double margeEcran = 20;

  /// Marge latérale des en-têtes colorés et de l'écran des artistes.
  static const double margeEnTete = 24;

  /// Marge haute des écrans (zone de la barre d'état comprise).
  static const double margeHaute = 56;

  /// Écart minimal sous la barre d'état système (43.15).
  static const double sousBarreEtat = 16;

  /// Padding bas de la grille des artistes (sous le panneau du bas).
  static const double paddingBasGrille = 170;

  /// Marges du contenu sur PC (43.10).
  static const double margePc = 32;
}

/// Rayons (43.4).
class Rayons {
  static const double enTete = 36;
  static const double carteLarge = 28;
  static const double carte = 24;
  static const double carteListe = 20;
  static const double bouton = 18;
  static const double filtre = 18;
  static const double pastille = 16;
  static const double pastilleListe = 14;
  static const double serie = 20;
  static const double etiquetteIA = 12;
  static const double boutonFlottant = 20;
  static const double navPastille = 15;
  static const double surlignage = 6;
  static const double masque = 8;
  static const double barreProgression = 5;
  static const double focus = 16;
}

/// Tailles (43.4).
class Tailles {
  static const double boutonMin = 56;
  static const double lienMin = 44;
  static const double recherche = 52;
  static const double champMot = 60;
  static const double bordureChamp = 2;
  static const double navHauteur = 84;
  static const double navPastilleLargeur = 52;
  static const double navPastilleHauteur = 30;
  static const double navIcone = 22;
  static const double icone = 24;
  static const double iconeRecherche = 20;
  static const double avatar = 92;
  static const double avatarReglages = 48;
  static const double anneau = 4;
  static const double coche = 30;
  static const double cocheIcone = 16;
  static const double cocheBordure = 3;
  static const double boutonFlottant = 60;
  static const double boutonFlottantIcone = 26;
  static const double boutonFlottantBas = 104;
  static const double barreProgression = 10;
  static const double bandeau = 40;
  static const double panneauBas = 150;
  static const double barreLaterale = 240;
  static const double logoBarreLaterale = 40;
  static const double entreeLaterale = 52;
  static const double enTeteRevisions = 330;
  static const double enTeteFiche = 250;
  static const double chevauchementRevision = 130;
  static const double chevauchementFiche = 30;
  static const double contenuPcMax = 960;
  static const double carteRevisionPcMax = 640;
  static const double colonneMobileMax = 640;
  static const double illustrationVide = 96;
  static const double focusAnneau = 3;
  static const double focusDecalage = 2;
  static const double pouceCurseur = 24;
  static const double zoneTactileMin = 48;

  /// Écart entre la carte de révision et les réponses (positions 487 → 540 de la planche).
  static const double ecartReponses = 52;
  static const double ecartAide = 24;
  static const double squeletteCarteMot = 72;
}

/// Points de rupture (27.1, 43.10).
class Ruptures {
  static const double pc = 900;
  static const double ficheDeuxColonnes = 1100;
}

/// Opacités utilisées par le design.
class Opacites {
  static const double desactive = 0.4;
  static const double dateEnTete = 0.9;
  static const double sousTitreEnTete = 0.92;
  static const double pisteProgression = 0.28;
  static const double survol = 0.06;
  static const double appui = 0.08;
  static const double interrupteurInactif = 0.25;
}

/// Durées des mouvements (43.12).
class Durees {
  static const transition = Duration(milliseconds: 200);
  static const apparition = Duration(milliseconds: 150);
  static const pulsation = Duration(milliseconds: 1200);
  static const annulation = Duration(seconds: 5);
  static const messageSync = Duration(seconds: 3);
  static const antiRebond = Duration(milliseconds: 300);
}

/// Ombres (43.4).
class Ombres {
  static List<BoxShadow> carteRevision(Couleurs c) => [
    BoxShadow(offset: const Offset(0, 12), blurRadius: 32, color: c.violet.withValues(alpha: 0.22)),
  ];
  static List<BoxShadow> carteFiche(Couleurs c) => [
    BoxShadow(offset: const Offset(0, 8), blurRadius: 24, color: c.ombre.withValues(alpha: 0.08)),
  ];
  static List<BoxShadow> carteListe(Couleurs c) => [
    BoxShadow(offset: const Offset(0, 6), blurRadius: 18, color: c.ombre.withValues(alpha: 0.07)),
  ];
  static List<BoxShadow> panneauBas(Couleurs c) => [
    BoxShadow(offset: const Offset(0, -10), blurRadius: 30, color: c.ombre.withValues(alpha: 0.12)),
  ];
  static List<BoxShadow> boutonFlottant(Couleurs c) => [
    BoxShadow(offset: const Offset(0, 10), blurRadius: 24, color: c.rose.withValues(alpha: 0.45)),
  ];
}

/// Accès rapide aux couleurs du thème courant.
extension ContexteTheme on BuildContext {
  Couleurs get couleurs => Theme.of(this).extension<Couleurs>() ?? Couleurs.clair;
  bool get animationsReduites => MediaQuery.maybeDisableAnimationsOf(this) ?? false;
  bool get estPc => MediaQuery.sizeOf(this).width >= Ruptures.pc;
}
