// Prononciation vocale des mots : synthèse vocale de l'appareil (Web Speech API dans la PWA,
// moteur de synthèse d'Android sur le téléphone). Aucun serveur ni clé, fonctionne hors ligne
// si la voix anglaise est installée sur l'appareil.
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_tts/flutter_tts.dart';

import 'plateforme.dart';

const langueAnglaise = 'en-US';
const vitesseNormale = 0.45;
const vitesseLente = 0.25;

// Web Speech API : 1,0 est la vitesse normale.
const vitesseNormaleWeb = 0.9;
const vitesseLenteWeb = 0.55;

abstract class ServicePrononciation {
  /// Prononce [texte] en anglais ; [lent] pour une diction ralentie. Faux si impossible.
  Future<bool> prononcer(String texte, {bool lent = false});
  Future<void> arreter();

  /// État du moteur de synthèse, affiché dans les réglages pour le dépannage.
  Future<String> diagnostic();
}

class PrononciationAppareil implements ServicePrononciation {
  final FlutterTts _tts = FlutterTts();
  bool _pret = false;

  /// Délai maximal d'un appel au moteur : si le moteur de synthèse ne répond pas, flutter_tts
  /// garde la demande en attente indéfiniment (ni son ni message).
  static const delai = Duration(seconds: 4);

  Future<T?> _appel<T>(Future<dynamic> Function() appel) async {
    try {
      return await appel().timeout(delai) as T?;
    } catch (_) {
      return null;
    }
  }

  /// Moteur choisi dans les réglages d'Android ; anglais américain, à défaut britannique.
  Future<bool> _preparer() async {
    if (_pret) return true;
    for (final langue in const [langueAnglaise, 'en-GB']) {
      if (await _appel<Object>(() => _tts.setLanguage(langue)) == 1) {
        await _appel<Object>(() => _tts.setPitch(1.0));
        await _appel<Object>(() => _tts.awaitSpeakCompletion(false));
        return _pret = true;
      }
    }
    return false;
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
    if (!await _preparer()) return false;
    await _appel<Object>(() => _tts.stop());
    await _appel<Object>(() => _tts.setSpeechRate(lent ? vitesseLente : vitesseNormale));
    final resultat = await _appel<Object>(() => _tts.speak(texte));
    if (resultat == 1) return true;
    _pret = false; // moteur à réinitialiser au prochain essai
    return false;
  }

  @override
  Future<String> diagnostic() async {
    if (kIsWeb) return 'Synthèse vocale du navigateur.';
    final moteur = await _appel<Object>(() => _tts.getDefaultEngine);
    final disponible = await _appel<Object>(() => _tts.isLanguageAvailable(langueAnglaise));
    final installee = await _appel<Object>(() => _tts.isLanguageInstalled(langueAnglaise));
    return 'Moteur : ${moteur ?? 'aucun'} — anglais : '
        '${disponible == true ? (installee == false ? 'à télécharger' : 'disponible') : 'absent'}';
  }

  @override
  Future<void> arreter() async {
    await _appel<Object>(() => _tts.stop());
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

  @override
  Future<String> diagnostic() async => 'Moteur de test.';
}
