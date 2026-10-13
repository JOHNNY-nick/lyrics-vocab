// Implémentation web : rechargement de la PWA après une mise à jour (PWA-07).
import 'dart:async';
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

/// Prononce [texte] avec la meilleure voix anglaise du navigateur ; faux s'il n'en a aucune
/// (une voix française lirait le mot avec un accent français, voir DECISIONS.md).
Future<bool> prononcerNavigateur(String texte, {required double vitesse}) async {
  final synthese = web.window.speechSynthesis;
  final voix = await _voixAnglaise(synthese);
  if (voix == null) return false;
  if (synthese.speaking || synthese.pending) {
    synthese.cancel();
    // Chrome ignore parfois une lecture demandée juste après « cancel ».
    await Future<void>.delayed(const Duration(milliseconds: 80));
  }
  synthese.speak(
    web.SpeechSynthesisUtterance(texte)
      ..voice = voix
      ..lang = voix.lang
      ..rate = vitesse,
  );
  return true;
}

/// Voix anglaise préférée : naturelle (Edge), Google, puis toute voix en-US, en-GB, en-*.
/// La liste des voix arrive après le chargement de la page : on l'attend au besoin.
Future<web.SpeechSynthesisVoice?> _voixAnglaise(web.SpeechSynthesis synthese) async {
  var voix = synthese.getVoices().toDart;
  for (var i = 0; voix.isEmpty && i < 15; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    voix = synthese.getVoices().toDart;
  }
  int note(web.SpeechSynthesisVoice v) {
    final nom = v.name.toLowerCase();
    final langue = v.lang.toLowerCase().replaceAll('_', '-');
    return (nom.contains('natural') ? 8 : 0) +
        (nom.contains('google') ? 4 : 0) +
        (langue == 'en-us' ? 2 : (langue == 'en-gb' ? 1 : 0));
  }

  final anglaises = voix.where((v) => v.lang.toLowerCase().startsWith('en')).toList()
    ..sort((a, b) => note(b) - note(a));
  return anglaises.isEmpty ? null : anglaises.first;
}

/// Reconnaissance vocale de Chrome/Edge (préfixe webkit, appelée directement : l'extension du
/// paquet speech_to_text échoue en compilation release).
@JS('webkitSpeechRecognition')
extension type _Reconnaissance._(JSObject _) implements JSObject {
  external factory _Reconnaissance();
  external set lang(String valeur);
  external set continuous(bool valeur);
  external set interimResults(bool valeur);
  external set maxAlternatives(int valeur);
  external set onresult(JSFunction rappel);
  external set onerror(JSFunction rappel);
  external set onend(JSFunction rappel);
  external void start();
  external void stop();
}

const _silenceFinDictee = Duration(milliseconds: 2500);
const _attenteParoleMax = Duration(seconds: 8);
const _dicteeMax = Duration(seconds: 30);

/// Dicte en [langue] jusqu'à 2,5 s de silence (8 s sans parole, 30 s au plus) ; [surTexte]
/// reçoit tout le texte reconnu, [surFin] est appelé à l'arrêt. Parmi les transcriptions
/// possibles, celle qui contient [motAttendu] est préférée (mot souvent mal reconnu avec un
/// accent). Retourne la fonction d'arrêt, ou null si la reconnaissance est absente.
void Function()? dicterNavigateur({
  required String langue,
  String? motAttendu,
  required void Function(String texte, bool fin) surTexte,
  required void Function() surFin,
}) {
  if (!web.window.hasProperty('webkitSpeechRecognition'.toJS).toDart) return null;
  final reconnaissance = _Reconnaissance()
    ..lang = langue
    ..continuous =
        true // pas d'arrêt à la première pause : le silence est mesuré ici
    ..interimResults = true
    ..maxAlternatives = 5;
  Timer? silence;
  void arreter() {
    silence?.cancel();
    reconnaissance.stop();
  }

  silence = Timer(_attenteParoleMax, arreter);
  final maximum = Timer(_dicteeMax, arreter);
  final cible = motAttendu?.toLowerCase();

  String choisir(web.SpeechRecognitionResult resultat) {
    if (cible != null) {
      for (var j = 0; j < resultat.length; j++) {
        final t = resultat.item(j).transcript;
        if (t.toLowerCase().contains(cible)) return t;
      }
    }
    return resultat.item(0).transcript;
  }

  reconnaissance.onresult = ((web.SpeechRecognitionEvent evenement) {
    final resultats = evenement.results;
    final morceaux = <String>[];
    var fin = true;
    for (var i = 0; i < resultats.length; i++) {
      final resultat = resultats.item(i);
      morceaux.add(choisir(resultat).trim());
      fin = fin && resultat.isFinal;
    }
    surTexte(morceaux.where((m) => m.isNotEmpty).join(' '), fin);
    silence?.cancel();
    silence = Timer(_silenceFinDictee, arreter);
  }).toJS;
  reconnaissance.onerror = ((JSObject _) {}).toJS; // « onend » suit toujours une erreur
  reconnaissance.onend = ((JSObject _) {
    silence?.cancel();
    maximum.cancel();
    surFin();
  }).toJS;
  reconnaissance.start();
  return arreter;
}
