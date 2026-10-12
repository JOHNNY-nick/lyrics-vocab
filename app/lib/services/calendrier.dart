// Jour local et dates d'échéance, équivalent de backend/app/services/calendrier.py (20.6).

/// Heure au format « HH:MM » vers (heures, minutes).
(int, int) lireHeure(String heure) {
  final morceaux = heure.split(':');
  return (int.parse(morceaux[0]), morceaux.length > 1 ? int.parse(morceaux[1]) : 0);
}

/// Jour local = date de (heure locale − heure de changement de jour) (ALG-14).
/// [heureLocale] est l'heure murale de l'appareil ; le calcul se fait sur l'heure murale pour
/// ne pas dériver au changement d'heure (ALG-13).
DateTime jourLocalDepuisHeureLocale(DateTime heureLocale, String heureChangement) {
  final (h, m) = lireHeure(heureChangement);
  final murale = DateTime.utc(
    heureLocale.year,
    heureLocale.month,
    heureLocale.day,
    heureLocale.hour,
    heureLocale.minute,
    heureLocale.second,
  );
  final decale = murale.subtract(Duration(hours: h, minutes: m));
  return DateTime.utc(decale.year, decale.month, decale.day);
}

/// Jour local d'un instant, au fuseau de l'appareil.
DateTime jourLocal(DateTime instant, String heureChangement) =>
    jourLocalDepuisHeureLocale(instant.toLocal(), heureChangement);

/// Jour de la réponse + intervalle, en calendrier local (dates UTC sans heure).
DateTime datePrevue(DateTime jourReponse, int intervalle) =>
    DateTime.utc(jourReponse.year, jourReponse.month, jourReponse.day + intervalle);

/// Date simple AAAA-MM-JJ.
String formatDate(DateTime jour) =>
    '${jour.year.toString().padLeft(4, '0')}-${jour.month.toString().padLeft(2, '0')}-'
    '${jour.day.toString().padLeft(2, '0')}';

/// Lecture d'une date simple AAAA-MM-JJ en date UTC sans heure.
DateTime lireDate(String texte) {
  final d = DateTime.parse(texte.substring(0, 10));
  return DateTime.utc(d.year, d.month, d.day);
}

/// Date ISO 8601 en UTC avec le suffixe Z.
String formatUtc(DateTime instant) => instant.toUtc().toIso8601String();
