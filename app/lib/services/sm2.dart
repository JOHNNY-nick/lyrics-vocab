// SM-2 adapté, équivalent exact de backend/app/services/sm2.py (REV-04, ALG-11, ALG-12).

const double faciliteInitiale = 2.5;
const double faciliteMin = 1.3;
const int intervalleMaxDefaut = 365;
const int noteReussiteMin = 3;
const int seuilAcquisDefaut = 21;

/// Notes de la table F.2.
class Notes {
  static const neSavaisPas = 1;
  static const savais = 4;
  static const facile = 5;
  static const verdicts = {'correct': 4, 'proche': 3, 'incorrect': 1};
}

class EtatRevision {
  const EtatRevision({this.repetitions = 0, this.facilite = faciliteInitiale, this.intervalleJours = 0});

  final int repetitions;
  final double facilite;
  final int intervalleJours;

  @override
  bool operator ==(Object other) =>
      other is EtatRevision &&
      other.repetitions == repetitions &&
      other.facilite == facilite &&
      other.intervalleJours == intervalleJours;

  @override
  int get hashCode => Object.hash(repetitions, facilite, intervalleJours);

  @override
  String toString() => 'EtatRevision($repetitions, $facilite, $intervalleJours)';
}

double _arrondir(double valeur, int decimales) {
  final facteur = _puissance10(decimales);
  return (valeur * facteur).round() / facteur;
}

double _puissance10(int n) {
  var resultat = 1.0;
  for (var i = 0; i < n; i++) {
    resultat *= 10;
  }
  return resultat;
}

/// État suivant pour la note [q] (0 à 5).
EtatRevision appliquerSm2(EtatRevision etat, int q, {int intervalleMax = intervalleMaxDefaut}) {
  if (q < noteReussiteMin) {
    return EtatRevision(repetitions: 0, facilite: _arrondir(etat.facilite, 2), intervalleJours: 1);
  }
  int intervalle;
  if (etat.repetitions == 0) {
    intervalle = 1;
  } else if (etat.repetitions == 1) {
    intervalle = 3;
  } else {
    intervalle = _arrondir(etat.intervalleJours * etat.facilite, 6).ceil();
  }
  final brute = etat.facilite + 0.1 - (5 - q) * (0.08 + (5 - q) * 0.02);
  final facilite = brute < faciliteMin ? faciliteMin : brute;
  return EtatRevision(
    repetitions: etat.repetitions + 1,
    facilite: _arrondir(facilite, 2),
    intervalleJours: intervalle > intervalleMax ? intervalleMax : intervalle,
  );
}

/// Niveau du mot après une réponse (REV-09).
String niveauDepuisEtat(
  EtatRevision etat,
  int derniereNote, {
  int seuilAcquisJours = seuilAcquisDefaut,
  String niveauActuel = 'nouveau',
}) {
  if (derniereNote < noteReussiteMin) {
    return niveauActuel == 'nouveau' ? 'nouveau' : 'en_cours';
  }
  if (etat.intervalleJours > seuilAcquisJours) return 'acquis';
  return 'en_cours';
}
