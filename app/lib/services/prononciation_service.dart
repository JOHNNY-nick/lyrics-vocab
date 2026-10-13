// Prononciation vocale des mots : synthèse vocale de l'appareil (Web Speech API dans la PWA,
// moteur de synthèse d'Android sur le téléphone). Aucun serveur ni clé, fonctionne hors ligne
// si la voix anglaise est installée sur l'appareil.
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_tts/flutter_tts.dart';

import 'plateforme.dart';

const langueAnglaise = 'en-US';
const vitesseNormale = 0.45;
const vitesseLente = 0.25;
const moteurGoogle = 'com.google.android.tts';

// Web Speech API : 1,0 est la vitesse normale.
const vitesseNormaleWeb = 0.9;
const vitesseLenteWeb = 0.55;

abstract class ServicePrononciation {
  /// Prononce [texte] en anglais ; [lent] pour une diction ralentie. Faux si impossible.
  Future<bool> prononcer(String texte, {bool lent = false});
  Future<void> arreter();
}

class PrononciationAppareil implements ServicePrononciation {
  final FlutterTts _tts = FlutterTts();
  bool? _pret;

  /// Moteur Google s'il est installé (meilleures voix anglaises que celui du fabricant), puis
  /// anglais américain, à défaut britannique. Faux si aucune voix anglaise n'est disponible :
  /// mieux vaut un message qu'un mot lu avec la voix française.
  Future<bool> _preparer() async {
    if (_pret != null) return _pret!;
    try {
      final moteurs = (await _tts.getEngines as List?)?.cast<Object?>() ?? const [];
      if (moteurs.contains(moteurGoogle)) await _tts.setEngine(moteurGoogle);
    } catch (_) {}
    var langue = '';
    for (final candidate in const [langueAnglaise, 'en-GB']) {
      if (await _tts.isLanguageAvailable(candidate) == true) {
        langue = candidate;
        break;
      }
    }
    if (langue.isEmpty) return _pret = false;
    await _tts.setLanguage(langue);
    await _tts.setPitch(1.0);
    await _tts.awaitSpeakCompletion(false);
    return _pret = true;
  }

  @override
  Future<bool> prononcer(String texte, {bool lent = false}) async {
    if (kIsWeb) {
      try {
        return await prononcerNavigateur(texte, vitesse: lent ? vitesseLenteWeb : vitesseNormaleWeb);
      } catch (_) {
        return false;
      }
    }
    try {
      if (!await _preparer()) return false;
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
