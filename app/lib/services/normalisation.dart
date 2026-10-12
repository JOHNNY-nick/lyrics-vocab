// Normalisation du terme, équivalent de backend/app/services/normalisation.py (B.5, ALG-01).
import 'package:unorm_dart/unorm_dart.dart' as unorm;

const int longueurMaxTerme = 100;
const int motsMax = 6;

final _espaces = RegExp(r'\s+', unicode: true);
final _ponctuationBord = RegExp(r"^[^\p{L}\p{N}_']+|[^\p{L}\p{N}_']+$", unicode: true);
final _lettre = RegExp(r'\p{L}', unicode: true);
final _marques = RegExp(r'\p{M}', unicode: true);

String normaliser(String terme) {
  var t = unorm.nfkc(terme);
  t = t.replaceAll('’', "'").replaceAll('‘', "'").replaceAll('ʼ', "'");
  t = t.toLowerCase();
  t = t.replaceAll(_espaces, ' ').trim();
  t = t.replaceAll(_ponctuationBord, '');
  while (t.startsWith("'")) {
    t = t.substring(1);
  }
  while (t.endsWith("'")) {
    t = t.substring(0, t.length - 1);
  }
  return t;
}

int compterMots(String termeNormalise) => termeNormalise.split(' ').where((m) => m.isNotEmpty).length;

/// Résultat de la validation : le terme normalisé, ou le message d'erreur à afficher.
class ValidationTerme {
  const ValidationTerme._(this.normalise, this.erreur);
  const ValidationTerme.ok(String normalise) : this._(normalise, null);
  const ValidationTerme.erreur(String message) : this._(null, message);

  final String? normalise;
  final String? erreur;
  bool get valide => erreur == null;
}

/// Mêmes règles que valider_terme côté serveur (le serveur fait foi, ALG-02).
ValidationTerme validerTerme(String terme, {required String messageVide, required String messageTropLong}) {
  final brut = terme.trim();
  if (brut.runes.length > longueurMaxTerme) return ValidationTerme.erreur(messageTropLong);
  final normalise = normaliser(brut);
  if (normalise.isEmpty || !_lettre.hasMatch(normalise)) {
    return ValidationTerme.erreur(messageVide);
  }
  if (compterMots(normalise) > motsMax || normalise.runes.length > longueurMaxTerme) {
    return ValidationTerme.erreur(messageTropLong);
  }
  return ValidationTerme.ok(normalise);
}

/// Copie sans accents, pour les recherches insensibles aux accents (MAQ-15).
String sansAccents(String texte) => unorm.nfd(texte).replaceAll(_marques, '');

/// Forme de comparaison : minuscules, sans accents, apostrophes droites.
String formeComparable(String texte) => sansAccents(texte.toLowerCase().replaceAll('’', "'"));
