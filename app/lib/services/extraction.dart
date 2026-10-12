// Outils sur les extraits : masquage du mot et conversion des positions (MAQ-05, 18.2).

/// Convertit un indice en points de code (fourni par le serveur) en indice UTF-16 (Dart).
int indiceUtf16(String texte, int pointsDeCode) {
  var unites = 0;
  var compte = 0;
  for (final rune in texte.runes) {
    if (compte >= pointsDeCode) break;
    unites += rune > 0xFFFF ? 2 : 1;
    compte++;
  }
  return unites;
}

/// Bornes UTF-16 de la surbrillance, ou null si elles sont incohérentes.
(int, int)? bornesSurbrillance(String texte, int debut, int fin) {
  final d = indiceUtf16(texte, debut);
  final f = indiceUtf16(texte, fin);
  if (d < 0 || f <= d || f > texte.length) return null;
  return (d, f);
}

/// Remplace le mot par des tirets bas de la longueur du mot (points de code).
String masquerMot(String texte, int debut, int fin) {
  final bornes = bornesSurbrillance(texte, debut, fin);
  if (bornes == null) return texte;
  final (d, f) = bornes;
  return texte.substring(0, d) + '_' * (fin - debut) + texte.substring(f);
}
