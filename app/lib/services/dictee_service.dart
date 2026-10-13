// Réponse dictée à voix haute dans les exercices : reconnaissance vocale de l'appareil
// (Web Speech API dans Chrome/Edge, service de reconnaissance d'Android sur le téléphone),
// en anglais. Le texte reconnu remplit le champ de réponse, puis la réponse est vérifiée.
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

const langueDictee = 'en-US';
const dureeEcouteMax = Duration(seconds: 30);
const silenceFin = Duration(seconds: 3);

/// Texte reconnu ; [fin] vaut vrai pour le résultat définitif.
typedef SurTexteDicte = void Function(String texte, bool fin);

abstract class ServiceDictee {
  /// Prépare la reconnaissance (demande l'accès au micro) ; faux si indisponible ou refusé.
  Future<bool> preparer();

  /// Écoute jusqu'à un silence de 3 s ou 30 s au plus ; [surFin] est appelé quand l'écoute
  /// s'arrête, même sans texte reconnu.
  Future<void> ecouter({required SurTexteDicte surTexte, required void Function() surFin});
  Future<void> arreter();
}

class DicteeAppareil implements ServiceDictee {
  final SpeechToText _reconnaissance = SpeechToText();
  bool? _pret;
  void Function()? _surFin;

  @override
  Future<bool> preparer() async {
    if (_pret == true) return true;
    try {
      _pret = await _reconnaissance.initialize(
        onStatus: (statut) {
          if (statut == SpeechToText.doneStatus || statut == SpeechToText.notListeningStatus) _terminer();
        },
        onError: (_) => _terminer(),
      );
    } catch (_) {
      _pret = false;
    }
    return _pret!;
  }

  void _terminer() {
    final surFin = _surFin;
    _surFin = null;
    surFin?.call();
  }

  @override
  Future<void> ecouter({required SurTexteDicte surTexte, required void Function() surFin}) async {
    _surFin = surFin;
    await _reconnaissance.listen(
      onResult: (SpeechRecognitionResult r) => surTexte(r.recognizedWords, r.finalResult),
      listenOptions: SpeechListenOptions(
        // Android attend « en_US », le navigateur « en-US ».
        localeId: kIsWeb ? langueDictee : langueDictee.replaceAll('-', '_'),
        listenFor: dureeEcouteMax,
        pauseFor: silenceFin,
        partialResults: true,
        listenMode: ListenMode.dictation,
        cancelOnError: true,
      ),
    );
  }

  @override
  Future<void> arreter() async {
    try {
      await _reconnaissance.stop();
    } catch (_) {}
    _terminer();
  }
}

/// Tests : renvoie le texte programmé dans [phrase] sans micro.
class DicteeNeutre implements ServiceDictee {
  DicteeNeutre({this.phrase, this.disponible = true});
  String? phrase;
  bool disponible;

  @override
  Future<bool> preparer() async => disponible;

  @override
  Future<void> ecouter({required SurTexteDicte surTexte, required void Function() surFin}) async {
    final texte = phrase;
    if (texte != null) surTexte(texte, true);
    surFin();
  }

  @override
  Future<void> arreter() async {}
}
