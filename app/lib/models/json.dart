// Aides de conversion JSON communes aux modèles (FLU-03).
import '../services/calendrier.dart';

DateTime? lireInstant(Object? valeur) =>
    valeur == null || valeur == '' ? null : DateTime.parse(valeur as String).toUtc();

DateTime? lireJour(Object? valeur) => valeur == null || valeur == '' ? null : lireDate(valeur as String);

String? ecrireInstant(DateTime? valeur) => valeur == null ? null : formatUtc(valeur);

String? ecrireJour(DateTime? valeur) => valeur == null ? null : formatDate(valeur);

int lireEntier(Object? valeur, [int defaut = 0]) => valeur == null ? defaut : (valeur as num).toInt();

double lireReel(Object? valeur, [double defaut = 0]) => valeur == null ? defaut : (valeur as num).toDouble();

/// Valeur sentinelle de copyWith pour distinguer « absent » de « null ».
const absent = Object();
