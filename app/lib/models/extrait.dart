import 'json.dart';

/// Extrait de chanson avec positions de surbrillance (points de code).
class Extrait {
  const Extrait({
    required this.id,
    required this.motId,
    required this.texte,
    required this.surbrillanceDebut,
    required this.surbrillanceFin,
    required this.horsListe,
    required this.titre,
    required this.artiste,
    this.url,
    this.deletedAt,
  });

  final String id;
  final String motId;
  final String texte;
  final int surbrillanceDebut;
  final int surbrillanceFin;
  final bool horsListe;
  final String titre;
  final String artiste;

  /// Lien vers la chanson (Deezer ou Genius) fourni par le serveur, s'il a été trouvé.
  final String? url;

  /// Lien à ouvrir : celui du serveur, sinon une recherche YouTube de la chanson.
  /// Lien principal (préférence de l'utilisateur) : la chanson sur YouTube.
  String get lienEcoute =>
      'https://www.youtube.com/results?search_query=${Uri.encodeQueryComponent('$artiste $titre')}';

  /// Lien secondaire : la chanson sur Deezer, quand elle y a été trouvée.
  String? get lienDeezer => url;
  final DateTime? deletedAt;

  /// Lit la forme de la fiche (morceau imbriqué) ou celle du pull (titre et artiste à plat).
  factory Extrait.fromJson(Map<String, dynamic> json, {String? motId}) {
    final morceau = json['morceau'] as Map<String, dynamic>?;
    return Extrait(
      id: json['id'] as String,
      motId: (json['mot_id'] as String?) ?? motId ?? '',
      texte: json['texte'] as String,
      surbrillanceDebut: lireEntier(json['surbrillance_debut']),
      surbrillanceFin: lireEntier(json['surbrillance_fin']),
      horsListe: json['hors_liste'] as bool? ?? false,
      titre: (morceau?['titre'] ?? json['titre'] ?? '') as String,
      artiste: (morceau?['artiste'] ?? json['artiste'] ?? '') as String,
      url: (morceau?['url_genius'] ?? json['url_genius']) as String?,
      deletedAt: lireInstant(json['deleted_at']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'mot_id': motId,
    'texte': texte,
    'surbrillance_debut': surbrillanceDebut,
    'surbrillance_fin': surbrillanceFin,
    'hors_liste': horsListe,
    'titre': titre,
    'artiste': artiste,
    'url_genius': url,
    'deleted_at': ecrireInstant(deletedAt),
  };

  Extrait copyWith({String? motId}) => Extrait(
    id: id,
    motId: motId ?? this.motId,
    texte: texte,
    surbrillanceDebut: surbrillanceDebut,
    surbrillanceFin: surbrillanceFin,
    horsListe: horsListe,
    titre: titre,
    artiste: artiste,
    url: url,
    deletedAt: deletedAt,
  );
}
