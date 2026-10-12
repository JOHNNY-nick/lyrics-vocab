// Implémentation web : rechargement de la PWA après une mise à jour (PWA-07).
import 'package:web/web.dart' as web;

void rechargerPage() => web.window.location.reload();

String originePage() => web.window.location.origin;
