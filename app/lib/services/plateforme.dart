// Fonctions propres au web isolées derrière une importation conditionnelle (FLU-04).
export 'plateforme_neutre.dart' if (dart.library.js_interop) 'plateforme_web.dart';
