// Détection du réseau (SYN-06) : connectivity_plus sur Android, implémentation neutre sur le web.
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import 'sync_service.dart';

abstract class ServiceConnectivite {
  Future<TypeReseau> type();

  /// Émet à chaque changement de réseau.
  Stream<TypeReseau> get changements;
}

class ConnectiviteAndroid implements ServiceConnectivite {
  final _connectivite = Connectivity();

  static TypeReseau _convertir(List<ConnectivityResult> resultats) {
    if (resultats.contains(ConnectivityResult.wifi) || resultats.contains(ConnectivityResult.ethernet)) {
      return TypeReseau.wifi;
    }
    if (resultats.contains(ConnectivityResult.mobile)) return TypeReseau.mobile;
    if (resultats.contains(ConnectivityResult.vpn) || resultats.contains(ConnectivityResult.other)) {
      return TypeReseau.autre;
    }
    return TypeReseau.aucun;
  }

  @override
  Future<TypeReseau> type() async => _convertir(await _connectivite.checkConnectivity());

  @override
  Stream<TypeReseau> get changements => _connectivite.onConnectivityChanged.map(_convertir);
}

/// Web et tests : le réseau est considéré présent ; seul /api/health fait foi.
class ConnectiviteNeutre implements ServiceConnectivite {
  ConnectiviteNeutre([this.valeur = TypeReseau.wifi]);
  TypeReseau valeur;
  final _flux = StreamController<TypeReseau>.broadcast();

  void changer(TypeReseau nouveau) {
    valeur = nouveau;
    _flux.add(nouveau);
  }

  @override
  Future<TypeReseau> type() async => valeur;

  @override
  Stream<TypeReseau> get changements => _flux.stream;
}
