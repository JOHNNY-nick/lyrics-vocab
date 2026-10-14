// Notifications de Lyrics & Vocab reçues par la page de lancement (adresse fixe) : un mot au
// hasard ; la toucher rouvre la page de lancement, qui ouvre la fiche dans l'application.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (evenement) => evenement.waitUntil(self.clients.claim()));

self.addEventListener('push', (evenement) => {
  let donnees = {};
  try {
    donnees = evenement.data ? evenement.data.json() : {};
  } catch (e) {}
  evenement.waitUntil(
    self.registration.showNotification(donnees.titre || 'Lyrics & Vocab', {
      body: donnees.texte || '',
      icon: 'icone.png',
      tag: 'mot',
      data: { mot: donnees.mot_id || null },
    })
  );
});

self.addEventListener('notificationclick', (evenement) => {
  evenement.notification.close();
  const mot = evenement.notification.data && evenement.notification.data.mot;
  const cible = new URL(mot ? './?mot=' + encodeURIComponent(mot) : './', self.registration.scope).href;
  evenement.waitUntil(self.clients.openWindow(cible));
});
