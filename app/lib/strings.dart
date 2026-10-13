// Textes de l'interface regroupés en un seul fichier (UI-09, catalogue 21.1, libellés du design).
class S {
  // Catalogue 21.1
  static const termeVide = 'Saisis un mot ou une expression.';
  static const termeTropLong = 'Un mot ou une expression de 6 mots au plus, sans dépasser 100 caractères.';
  static const motDejaPresent = 'Ce mot est déjà dans ta bibliothèque.';
  static const enrichissementEnCours = 'Recherche d\'un extrait, traduction et explication…';
  static const aucunExtrait = 'Aucun extrait trouvé pour ce mot dans les chansons de tes artistes.';
  static const iaIndisponible = 'Explication indisponible pour le moment, elle sera ajoutée plus tard.';
  static const traductionIndisponible = 'Traduction indisponible, nouvelle tentative possible.';
  static const horsLigne = 'Hors ligne — tes réponses sont enregistrées et seront envoyées plus tard.';
  static const pcInjoignable =
      'Ton PC est injoignable (éteint, en veille, ou Tailscale coupé). L\'application reste utilisable.';
  static const syncTerminee = 'Synchronisation terminée.';
  static String actionsEnAttente(int n) =>
      n == 1 ? '1 action en attente d\'envoi.' : '$n actions en attente d\'envoi.';
  static const erreurSync = 'Une action n\'a pas pu être envoyée. Voir « À examiner » dans les Réglages.';
  static const serveurMuet = 'Le serveur ne répond pas. Vérifie que ton PC est allumé, puis réessaie.';
  static const quotaAtteint = 'Limite journalière atteinte pour ce service. Réessaie demain.';
  static const suppressionQuestion = 'Supprimer ce mot ? Il disparaîtra de tes appareils.';
  static const exerciceIndisponible = 'L\'exercice n\'est pas disponible pour le moment.';
  static String aucuneRevision(String? date) => date == null
      ? 'Rien à réviser aujourd\'hui.'
      : 'Rien à réviser aujourd\'hui. Prochaine révision : $date.';
  static const notificationRefusee =
      'Les rappels sont désactivés : autorise les notifications dans les réglages du téléphone.';
  static const etiquetteIA = 'Générée automatiquement';
  static const horsListe = 'Artiste hors de ta liste';
  static const nouvelleVersion = 'Une nouvelle version est disponible.';
  static const pluslongQuePrevu = 'Cela prend plus de temps que prévu, la fiche se complétera toute seule.';
  static const erreurGenerique = 'Une erreur est survenue. Réessaie dans un instant.';
  static const horsLigneFonction =
      'Cette fonction a besoin de ton PC : elle sera disponible quand il sera joignable.';
  static const misAJourRequise = 'Mets l\'application à jour pour continuer à synchroniser.';
  static const donneesLocalesVides = 'Tes données reviendront à la prochaine synchronisation avec ton PC.';
  static const verifierTailscale = 'Vérifie que l\'application Tailscale est connectée.';

  // Navigation (43.7)
  static const navRevisions = 'Révisions';
  static const navMots = 'Mots';
  static const navAjouter = 'Ajouter';
  static const navReglages = 'Réglages';
  static const navigationPrincipale = 'Navigation principale';
  static const nomApplication = 'Lyrics & Vocab';
  static const accroche = 'Apprends l\'anglais avec tes chansons';

  // Choix des artistes (43.6)
  static const bienvenue = 'Bienvenue';
  static String choisis(int n) => n <= 1 ? '$n choisi' : '$n choisis';
  static const choisisArtistes = 'Choisis tes artistes préférés';
  static const sousTitreArtistes =
      'Les extraits de tes mots viendront de leurs chansons. Tu pourras changer plus tard.';
  static const rechercherArtiste = 'Rechercher un artiste';
  static String continuerAvec(int n) => n == 1 ? 'Continuer avec 1 artiste' : 'Continuer avec $n artistes';
  static const choisisAuMoinsUn = 'Choisis au moins un artiste';
  static const passer = 'Passer, je choisirai plus tard';
  static const aucunArtiste = 'Aucun artiste trouvé';
  static const maxArtistes = '30 artistes au maximum';
  static const reessayer = 'Réessayer';

  // Révisions du jour (43.6, 27.2)
  static const revisionsDuJour = 'Révisions du jour';
  static String serie(int n) => 'Série de $n jours';
  static String progression(int k, int n) => '$k / $n mots';
  static const devineLeMot = 'DEVINE LE MOT';
  static const traduisLeMot = 'TRADUIS CE MOT';
  static const extraitDeTaListe = 'Extrait d\'une chanson de ta liste';
  static const extraitHorsListe = 'Extrait d\'une chanson hors de ta liste';
  static const pasDExtrait = 'Pas encore d\'extrait pour ce mot';
  static const reveler = 'Révéler';
  static const neSavaisPas = 'Je ne savais pas';
  static const savais = 'Je savais';
  static const facile = 'Facile';
  static const aideBoutons = 'Les boutons s\'activent après avoir révélé la réponse.';
  static String motsAReviser(int n) => n == 1 ? '1 mot à réviser' : '$n mots à réviser';
  static String dureeEstimee(int minutes) => 'environ $minutes minute${minutes > 1 ? 's' : ''}';
  static const commencer = 'Commencer';
  static const reponseEnregistree = 'Réponse enregistrée';
  static const annuler = 'Annuler';
  static const fermerSession = 'Quitter la session ?';
  static const fermerSessionTexte = 'Tes réponses déjà données sont enregistrées.';
  static const quitter = 'Quitter';
  static const continuer = 'Continuer';
  static const ajouterUnMot = 'Ajouter un mot';
  static const fermer = 'Fermer';

  // Exercice (43.9)
  static const traduisEnAnglais = 'TRADUIS EN ANGLAIS';
  static const taReponse = 'Ta traduction en anglais';
  static const valider = 'Valider';
  static const correct = 'Correct';
  static const presque = 'Presque';
  static const incorrect = 'Incorrect';
  static const evaluationSimplifiee = 'Évaluation simplifiée';
  static const attendu = 'Traduction attendue';
  static const suivant = 'Suivant';

  // Récapitulatif (43.9)
  static const bienJoue = 'Bien joué';
  static const motsRevises = 'Mots révisés';
  static const reussites = 'Réussites';
  static String prochaineRevisionLe(String date) => 'Prochaine révision : $date';
  static const terminer = 'Terminer';
  static const sessionSuivante = 'Session suivante';

  // Fiche (43.6)
  static const ficheDuMot = 'Fiche du mot';
  static const argot = 'Argot';
  static const traduction = 'TRADUCTION';
  static const extrait = 'EXTRAIT';
  static String extraitNumero(int n) => 'EXTRAIT $n';
  static const explication = 'EXPLICATION';
  static const prochaineRevision = 'Prochaine révision';
  static String echecs(int n) => n > 1 ? 'Échecs' : 'Échec';
  static const reessayerEnrichissement = 'Réessayer l\'enrichissement';
  static const supprimerCeMot = 'Supprimer ce mot';
  static const supprimer = 'Supprimer';
  static const motSupprime = 'Mot supprimé';
  static const plusDActions = 'Plus d\'actions';
  static const aucuneEcheance = '—';
  static const enAttenteEnrichissement = 'En attente d\'enrichissement';

  // Niveaux (21.3)
  static const nouveau = 'Nouveau';
  static const enCours = 'En cours';
  static const acquis = 'Acquis';
  static const tous = 'Tous';

  // Bibliothèque (43.6, 27.5)
  static const mesMots = 'Mes mots';
  static String nbMots(int n) => n <= 1 ? '$n mot' : '$n mots';
  static const rechercherMot = 'Rechercher un mot';
  static const effacerRecherche = 'Effacer la recherche';
  static const ajouteTonPremierMot = 'Ajoute ton premier mot';
  static const bibliothequeVideTexte = 'Les mots que tu ajoutes apparaîtront ici avec leur traduction.';
  static const aucunResultat = 'Aucun mot ne correspond.';
  static const trier = 'Trier';
  static const triAjoutRecent = 'Ajout récent';
  static const triAjoutAncien = 'Ajout ancien';
  static const triProchaineRevision = 'Prochaine révision';
  static const triAlpha = 'Ordre alphabétique';
  static const voir = 'Voir';
  static const actualiser = 'Actualiser';

  // Ajouter un mot (43.9, 27.3)
  static const aideChampMot = 'Un mot ou une expression en anglais';
  static const ajouter = 'Ajouter';
  static const derniersMots = 'Derniers mots ajoutés';
  static const voirLaFiche = 'Voir sa fiche';

  // Réglages (27.6, 43.9)
  static const reglages = 'Réglages';
  static const sectionArtistes = 'ARTISTES';
  static const sectionRevisions = 'RÉVISIONS';
  static const sectionRappels = 'RAPPELS';
  static const sectionSync = 'SYNCHRONISATION';
  static const sectionServeur = 'SERVEUR';
  static const sectionInformations = 'INFORMATIONS';
  static const sectionDonnees = 'DONNÉES';
  static const ajouterArtiste = 'Ajouter un artiste';
  static const modifierArtistes = 'Modifier mes artistes';
  static const aucunArtisteChoisi = 'Aucun artiste choisi pour le moment.';
  static const motsParSession = 'Mots par session';
  static const modeRevision = 'Mode de révision';
  static const modeRappel = 'Rappel';
  static const modeMelange = 'Mélange';
  static const heureChangementJour = 'Changement de jour';
  static const optionFacile = 'Proposer « Facile »';
  static const frequence = 'Fréquence';
  static const quotidien = 'Chaque jour';
  static const tousLes2Jours = 'Tous les 2 jours';
  static const desactive = 'Désactivé';
  static const heure = 'Heure';
  static const permissionNotifications = 'Notifications';
  static const autorisees = 'Autorisées';
  static const refusees = 'Refusées';
  static const autoriser = 'Autoriser';
  static const wifiSeulement = 'Wi-Fi seulement';
  static const synchroniserMaintenant = 'Synchroniser maintenant';
  static const derniereSync = 'Dernière synchronisation';
  static const jamais = 'Jamais';
  static const actionsAttente = 'Actions en attente';
  static const aExaminer = 'À examiner';
  static const rienAExaminer = 'Rien à examiner.';
  static const abandonner = 'Abandonner';
  static const adresseServeur = 'Adresse du serveur';
  static const tester = 'Tester';
  static const adresseInvalide = 'Saisis une adresse https:// avec un nom de machine.';
  static const adresseOk = 'Serveur joignable, adresse enregistrée.';
  static const adresseKo = 'Le serveur ne répond pas à cette adresse.';
  static const version = 'Version';
  static const curseur = 'Curseur';
  static const ollama = 'IA (Ollama)';
  static const quotas = 'Quotas du jour';
  static const disponible = 'Disponible';
  static const indisponible = 'Indisponible';
  static const inconnu = 'Inconnu';
  static const erreursRecentes = 'Erreurs récentes';
  static const aucuneErreur = 'Aucune erreur récente.';
  static const exporter = 'Exporter mes données';
  static const exportPret = 'Tes données sont copiées dans le presse-papiers (format JSON).';
  static const syncMobileConfirmation = 'Tu es sur les données mobiles. Synchroniser quand même ?';
  static const confirmer = 'Confirmer';
  static const enregistre = 'Enregistré.';
  static const batterie = 'Optimisation de batterie';
  static const actualiserPage = 'Actualiser';
  static const ecouterChanson = 'Écouter la chanson';
  static String prononcer(String mot) => 'Écouter la prononciation de « $mot »';
  static const prononciationLente = 'Appui long : prononciation lente';
  static const prononciationImpossible =
      "Prononciation indisponible : installe une voix anglaise dans les réglages de synthèse vocale de l'appareil.";
  static const lienImpossible = "Impossible d'ouvrir le lien.";
  // Exercice d'utilisation du mot
  static const sEntrainer = "S'entraîner avec ce mot";
  static const exerciceTitre = 'Exercice';
  static const exerciceSousTitre = 'Traduis la phrase en anglais en utilisant le mot.';
  static const sessionExercices = "Session d'exercices";
  static const sessionExercicesTexte = 'Traduis des phrases avec tes mots du jour.';
  static const nouvellePhrase = 'Nouvelle phrase';
  static const exerciceSansTraduction =
      "L'exercice sera possible quand la traduction du mot sera disponible.";
  // Apparence
  static const sectionApparence = 'APPARENCE';
  static const theme = 'Thème';
  static const themeClair = 'Clair';
  static const themeSombre = 'Sombre';
  static const themeSysteme = 'Système';
  static const sauvegarde = 'Dernière sauvegarde';
  static const sauvegardeEchec = 'La sauvegarde quotidienne n\'a pas abouti : vérifie le PC.';
  static const batterieTexte =
      'Pour recevoir les rappels à l\'heure, exclue l\'application de l\'optimisation de batterie.';
}
