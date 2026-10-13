// Implémentation web : rechargement de la PWA après une mise à jour (PWA-07).
import 'package:web/web.dart' as web;

void rechargerPage() => web.window.location.reload();

String originePage() => web.window.location.origin;

/// Ouvre un lien dans un nouvel onglet, directement dans le geste de l'utilisateur.
Future<bool> ouvrirLien(String url) async {
  web.window.open(url, '_blank');
  return true;
}
