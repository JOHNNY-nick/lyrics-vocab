// Icônes et logo dessinés depuis les tracés SVG du design (43.7, 43.8, DES-06, DES-37).
import 'package:flutter/material.dart';

/// Analyseur minimal de l'attribut « d » SVG : M, L, H, V, Q, A, Z (absolus et relatifs).
Path cheminSvg(String d) {
  final jetons = RegExp(
    r'[MmLlHhVvQqAaZz]|-?\d*\.?\d+(?:e-?\d+)?',
  ).allMatches(d).map((m) => m.group(0)!).toList();
  final chemin = Path();
  var i = 0;
  var x = 0.0, y = 0.0, departX = 0.0, departY = 0.0;
  String commande = 'M';
  double n() => double.parse(jetons[i++]);
  bool estNombre() => i < jetons.length && !RegExp(r'^[A-Za-z]$').hasMatch(jetons[i]);
  while (i < jetons.length) {
    if (!estNombre()) commande = jetons[i++];
    final relatif = commande == commande.toLowerCase();
    switch (commande.toUpperCase()) {
      case 'M':
        final nx = n(), ny = n();
        x = relatif ? x + nx : nx;
        y = relatif ? y + ny : ny;
        chemin.moveTo(x, y);
        departX = x;
        departY = y;
        commande = relatif ? 'l' : 'L';
      case 'L':
        final nx = n(), ny = n();
        x = relatif ? x + nx : nx;
        y = relatif ? y + ny : ny;
        chemin.lineTo(x, y);
      case 'H':
        final nx = n();
        x = relatif ? x + nx : nx;
        chemin.lineTo(x, y);
      case 'V':
        final ny = n();
        y = relatif ? y + ny : ny;
        chemin.lineTo(x, y);
      case 'Q':
        var cx = n(), cy = n(), nx = n(), ny = n();
        if (relatif) {
          cx += x;
          cy += y;
          nx += x;
          ny += y;
        }
        chemin.quadraticBezierTo(cx, cy, nx, ny);
        x = nx;
        y = ny;
      case 'A':
        final rx = n(), ry = n(), rotation = n(), grand = n(), sens = n();
        var nx = n(), ny = n();
        if (relatif) {
          nx += x;
          ny += y;
        }
        chemin.arcToPoint(
          Offset(nx, ny),
          radius: Radius.elliptical(rx, ry),
          rotation: rotation,
          largeArc: grand != 0,
          clockwise: sens != 0,
        );
        x = nx;
        y = ny;
      case 'Z':
        chemin.close();
        x = departX;
        y = departY;
    }
  }
  return chemin;
}

/// Forme d'une icône : chemins, cercles et rectangles arrondis dans un repère 24 × 24.
class FormeIcone {
  const FormeIcone({this.chemins = const [], this.cercles = const [], this.rectangles = const []});
  final List<String> chemins;
  final List<(double, double, double)> cercles;
  final List<(double, double, double, double, double)> rectangles;
}

class Icones {
  static const revisions = FormeIcone(
    chemins: ['M12 3l2.6 5.6 6.1.7-4.5 4.2 1.2 6L12 16.5 6.6 19.5l1.2-6L3.3 9.3l6.1-.7z'],
  );
  static const mots = FormeIcone(rectangles: [(4, 4, 16, 16, 4)], chemins: ['M8 9h8M8 13h5']);
  static const ajouter = FormeIcone(cercles: [(12, 12, 9)], chemins: ['M12 8v8M8 12h8']);
  static const reglages = FormeIcone(cercles: [(12, 12, 3)], chemins: ['M12 3v3M12 18v3M3 12h3M18 12h3']);
  static const loupe = FormeIcone(cercles: [(11, 11, 7)], chemins: ['M20 20l-4-4']);
  static const coche = FormeIcone(chemins: ['M5 12.5l4.5 4.5L19 7.5']);
  static const plus = FormeIcone(chemins: ['M12 5v14M5 12h14']);
  static const fermer = FormeIcone(chemins: ['M6 6l12 12M18 6L6 18']);
  static const retour = FormeIcone(chemins: ['M15 18l-6-6 6-6']);
  static const tri = FormeIcone(chemins: ['M4 7h16M7 12h10M10 17h4']);
  static const plusDActions = FormeIcone(cercles: [(5, 12, 1), (12, 12, 1), (19, 12, 1)]);
  static const actualiser = FormeIcone(chemins: ['M20 12a8 8 0 1 1-2.3-5.6M20 4v4h-4']);
  static const etoile = revisions;
  static const progression = FormeIcone(cercles: [(12, 12, 8)], chemins: ['M12 4a8 8 0 0 1 8 8']);
  static const hautParleur = FormeIcone(
    chemins: ['M11 5L6 9H3v6h3l5 4V5z', 'M15.5 8.5a5 5 0 0 1 0 7', 'M18.5 5.5a9 9 0 0 1 0 13'],
  );
  static const micro = FormeIcone(
    rectangles: [(9, 3, 6, 11, 3)],
    chemins: ['M5 11a7 7 0 0 0 14 0', 'M12 18v3M9 21h6'],
  );
  static const stop = FormeIcone(rectangles: [(7, 7, 10, 10, 2)]);
  static const nuage = FormeIcone(chemins: ['M7 18h10a4 4 0 0 0 0-8 6 6 0 0 0-11.5 2A3 3 0 0 0 7 18z']);
}

/// Icône en tracé : trait 2, extrémités et jonctions arrondies, sans remplissage (43.7).
class IconeTrace extends StatelessWidget {
  const IconeTrace(this.forme, {super.key, this.taille = 24, this.couleur, this.epaisseur = 2, this.libelle});
  final FormeIcone forme;
  final double taille;
  final Color? couleur;
  final double epaisseur;
  final String? libelle;

  @override
  Widget build(BuildContext context) {
    final dessin = CustomPaint(
      size: Size.square(taille),
      painter: _PeintreIcone(forme, couleur ?? IconTheme.of(context).color ?? Colors.black, epaisseur),
    );
    if (libelle == null) return ExcludeSemantics(child: dessin);
    return Semantics(label: libelle, child: dessin);
  }
}

class _PeintreIcone extends CustomPainter {
  _PeintreIcone(this.forme, this.couleur, this.epaisseur);
  final FormeIcone forme;
  final Color couleur;
  final double epaisseur;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final pinceau = Paint()
      ..color = couleur
      ..style = PaintingStyle.stroke
      ..strokeWidth = epaisseur
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    for (final (x, y, w, h, r) in forme.rectangles) {
      canvas.drawRRect(RRect.fromLTRBR(x, y, x + w, y + h, Radius.circular(r)), pinceau);
    }
    for (final (cx, cy, r) in forme.cercles) {
      canvas.drawCircle(Offset(cx, cy), r, pinceau);
    }
    for (final d in forme.chemins) {
      canvas.drawPath(cheminSvg(d), pinceau);
    }
  }

  @override
  bool shouldRepaint(_PeintreIcone ancien) =>
      ancien.forme != forme || ancien.couleur != couleur || ancien.epaisseur != epaisseur;
}

/// Symbole de l'application (43.8), repère 200 × 200.
class SymboleLogo extends StatelessWidget {
  const SymboleLogo({super.key, this.taille = 40});
  final double taille;

  /// En dessous de 28 px, le carré violet seul sans les arcs jaunes (43.8).
  static const tailleMinArcs = 28.0;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Icône Lyrics & Vocab',
    image: true,
    child: CustomPaint(size: Size.square(taille), painter: _PeintreLogo(taille >= tailleMinArcs)),
  );
}

class _PeintreLogo extends CustomPainter {
  _PeintreLogo(this.arcs);
  final bool arcs;

  static const violet = Color(0xFF6C4DFF);
  static const blanc = Color(0xFFFFFFFF);
  static const rose = Color(0xFFFF5C8A);
  static const jaune = Color(0xFFFFC93C);

  Paint _trait(Color c, double l) => Paint()
    ..color = c
    ..style = PaintingStyle.stroke
    ..strokeWidth = l
    ..strokeCap = StrokeCap.round
    ..isAntiAlias = true;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 200, size.height / 200);
    canvas.drawRRect(RRect.fromLTRBR(0, 0, 200, 200, const Radius.circular(46)), Paint()..color = violet);
    canvas.drawRRect(RRect.fromLTRBR(76, 34, 124, 120, const Radius.circular(24)), Paint()..color = blanc);
    canvas.drawPath(cheminSvg('M88 62H112M88 78H112M88 94H112'), _trait(rose, 7));
    canvas.drawPath(cheminSvg('M56 100a44 44 0 0 0 88 0'), _trait(blanc, 11));
    canvas.drawPath(cheminSvg('M100 144V164M76 166H124'), _trait(blanc, 11));
    if (arcs) {
      canvas.drawPath(cheminSvg('M36 74Q28 94 36 114M164 74Q172 94 164 114'), _trait(jaune, 9));
    }
  }

  @override
  bool shouldRepaint(_PeintreLogo ancien) => ancien.arcs != arcs;
}
