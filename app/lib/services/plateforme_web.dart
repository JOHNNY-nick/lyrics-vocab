// Implémentation web : rechargement de la PWA après une mise à jour (PWA-07).
import 'dart:js_interop';

import 'package:web/web.dart' as web;

void rechargerPage() => web.window.location.reload();

String originePage() => web.window.location.origin;

/// Ouvre un lien dans un nouvel onglet, directement dans le geste de l'utilisateur.
Future<bool> ouvrirLien(String url) async {
  web.window.open(url, '_blank');
  return true;
}

/// Prononce [texte] avec la synthèse vocale du navigateur (Web Speech API), voix anglaise.
bool prononcerNavigateur(String texte, {required double vitesse}) {
  final synthese = web.window.speechSynthesis;
  synthese.cancel();
  final enonce = web.SpeechSynthesisUtterance(texte)
    ..lang = 'en-US'
    ..rate = vitesse;
  final voix = synthese.getVoices().toDart;
  final anglaises = voix.where((v) => v.lang.toLowerCase().startsWith('en')).toList()
    ..sort((a, b) => (b.lang == 'en-US' ? 1 : 0) - (a.lang == 'en-US' ? 1 : 0));
  if (anglaises.isNotEmpty) enonce.voice = anglaises.first;
  synthese.speak(enonce);
  return true;
}
