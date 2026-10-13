// Réponse dictée à voix haute dans les exercices : reconnaissance vocale de l'appareil
// (Web Speech API dans Chrome/Edge, service de reconnaissance d'Android sur le téléphone),
// en anglais. Le texte reconnu remplit le champ de réponse, puis la réponse est vérifiée.
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'plateforme.dart';

const langueDictee = 'en-US';
const dureeEcouteMax = Duration(seconds: 30);
const silenceFin = Duration(milliseconds: 2500);

/// Texte reconnu ; [fin] vaut vrai pour le résultat définitif.
typedef SurTexteDicte = void Function(String texte, bool fin);

abstract class ServiceDictee {
  /// Prépare la reconnaissance (demande l'accès au micro) ; faux si indisponible ou refusé.
  Future<bool> preparer();

  /// Écoute jusqu'à un silence de 3 s ou 30 s au plus ; [surFin] est appelé quand l'écoute
  /// s'arrête, même sans texte reconnu.
  /// [motAttendu] : parmi les transcriptions possibles, celle qui contient ce mot est préférée.
  Future<void> ecouter({
    required SurTexteDicte surTexte,
    required void Function() surFin,
    String? motAttendu,
  });
  Future<void> arreter();
}

class DicteeAppareil implements ServiceDictee {
  final SpeechToText _reconnaissance = SpeechToText();
  bool? _pret;
  void Function()? _surFin;

  void Function()? _arretWeb;

  @override
  Future<bool> preparer() async {
    if (kIsWeb) return true; // l'accès au micro est demandé par le navigateur au démarrage
    if (_pret == true) return true;
    try {
      _pret = await _reconnaissance.initialize(
        // « notListening » arrive avant le résultat définitif : seule la fin (« done ») compte.
        onStatus: (statut) {
          if (statut == SpeechToText.doneStatus) _terminer();
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
  Future<void> ecouter({
    required SurTexteDicte surTexte,
    required void Function() surFin,
    String? motAttendu,
  }) async {
    _surFin = surFin;
    if (kIsWeb) {
      try {
        _arretWeb = dicterNavigateur(
          langue: langueDictee,
          motAttendu: motAttendu,
          surTexte: surTexte,
          surFin: _terminer,
        );
      } catch (_) {
        _arretWeb = null;
      }
      if (_arretWeb == null) _terminer();
      return;
    }
    await _reconnaissance.listen(
      onResult: (SpeechRecognitionResult r) {
        surTexte(_meilleure(r, motAttendu), r.finalResult);
        if (r.finalResult) _terminer();
      },
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

  static String _meilleure(SpeechRecognitionResult r, String? mot) {
    final cible = mot?.toLowerCase();
    if (cible != null) {
      for (final alternative in r.alternates) {
        if (alternative.recognizedWords.toLowerCase().contains(cible)) return alternative.recognizedWords;
      }
    }
    return r.recognizedWords;
  }

  @override
  Future<void> arreter() async {
    if (kIsWeb) {
      // L'arrêt déclenche « onend », qui transmet le dernier texte reconnu.
      final arret = _arretWeb;
      _arretWeb = null;
      if (arret != null) return arret();
      return _terminer();
    }
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

  String? motAttendu;

  @override
  Future<void> ecouter({
    required SurTexteDicte surTexte,
    required void Function() surFin,
    String? motAttendu,
  }) async {
    this.motAttendu = motAttendu;
    final texte = phrase;
    if (texte != null) surTexte(texte, true);
    surFin();
  }

  @override
  Future<void> arreter() async {}
}
