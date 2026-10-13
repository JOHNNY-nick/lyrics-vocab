// Implémentation neutre (Android, tests).
import 'package:url_launcher/url_launcher.dart';

/// Recharge la page (sans effet hors du web).
void rechargerPage() {}

/// Origine de la page (vide hors du web).
String originePage() => '';

/// Ouvre un lien dans l'application adaptée (Deezer, YouTube) ou le navigateur.
Future<bool> ouvrirLien(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

/// Synthèse vocale du navigateur : sans objet hors du web.
Future<bool> prononcerNavigateur(String texte, {required double vitesse}) async => false;

/// Reconnaissance vocale du navigateur : sans objet hors du web.
void Function()? dicterNavigateur({
  required String langue,
  String? motAttendu,
  required void Function(String texte, bool fin) surTexte,
  required void Function() surFin,
}) => null;
