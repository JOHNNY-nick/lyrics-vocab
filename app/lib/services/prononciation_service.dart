// Prononciation vocale des mots : synthèse vocale de l'appareil (Web Speech API dans la PWA,
// moteur de synthèse d'Android sur le téléphone). Aucun serveur ni clé, fonctionne hors ligne
// si la voix anglaise est installée sur l'appareil.
import 'package:flutter_tts/flutter_tts.dart';

const langueAnglaise = 'en-US';
const vitesseNormale = 0.45;
const vitesseLente = 0.25;

abstract class ServicePrononciation {
  /// Prononce [texte] en anglais ; [lent] pour une diction ralentie. Faux si impossible.
  Future<bool> prononcer(String texte, {bool lent = false});
  Future<void> arreter();
}

class PrononciationAppareil implements ServicePrononciation {
  final FlutterTts _tts = FlutterTts();
  bool _pret = false;

  Future<void> _preparer() async {
    if (_pret) return;
    await _tts.setLanguage(langueAnglaise);
    await _tts.setPitch(1.0);
    await _tts.awaitSpeakCompletion(false);
    _pret = true;
  }

  @override
  Future<bool> prononcer(String texte, {bool lent = false}) async {
    try {
      await _preparer();
      await _tts.stop();
      await _tts.setSpeechRate(lent ? vitesseLente : vitesseNormale);
      final resultat = await _tts.speak(texte);
      return resultat == 1 || resultat == true || resultat == null;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> arreter() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}

/// Tests : enregistre les demandes sans rien prononcer.
class PrononciationNeutre implements ServicePrononciation {
  final demandes = <(String, bool)>[];

  @override
  Future<bool> prononcer(String texte, {bool lent = false}) async {
    demandes.add((texte, lent));
    return true;
  }

  @override
  Future<void> arreter() async {}
}
