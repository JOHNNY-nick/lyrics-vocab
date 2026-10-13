// Implémentation web : rechargement de la PWA après une mise à jour (PWA-07).
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

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

/// Reconnaissance vocale de Chrome/Edge (préfixe webkit, appelée directement : l'extension du
/// paquet speech_to_text échoue en compilation release).
@JS('webkitSpeechRecognition')
extension type _Reconnaissance._(JSObject _) implements JSObject {
  external factory _Reconnaissance();
  external set lang(String valeur);
  external set continuous(bool valeur);
  external set interimResults(bool valeur);
  external set onresult(JSFunction rappel);
  external set onerror(JSFunction rappel);
  external set onend(JSFunction rappel);
  external void start();
  external void stop();
}

/// Dicte en [langue] : [surTexte] reçoit le texte reconnu (définitif ou non), [surFin] est
/// appelé à l'arrêt. Retourne la fonction d'arrêt, ou null si la reconnaissance est absente.
void Function()? dicterNavigateur({
  required String langue,
  required void Function(String texte, bool fin) surTexte,
  required void Function() surFin,
}) {
  if (!web.window.hasProperty('webkitSpeechRecognition'.toJS).toDart) return null;
  final reconnaissance = _Reconnaissance()
    ..lang = langue
    ..continuous =
        false // le navigateur s'arrête seul après une pause
    ..interimResults = true;
  reconnaissance.onresult = ((web.SpeechRecognitionEvent evenement) {
    final resultats = evenement.results;
    final texte = StringBuffer();
    var fin = true;
    for (var i = 0; i < resultats.length; i++) {
      final resultat = resultats.item(i);
      texte.write(resultat.item(0).transcript);
      fin = fin && resultat.isFinal;
    }
    surTexte(texte.toString().trim(), fin);
  }).toJS;
  reconnaissance.onerror = ((JSObject _) {}).toJS; // « onend » suit toujours une erreur
  reconnaissance.onend = ((JSObject _) => surFin()).toJS;
  reconnaissance.start();
  return () => reconnaissance.stop();
}
