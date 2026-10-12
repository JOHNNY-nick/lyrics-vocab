# Restauration d'une sauvegarde dans une base vide (SAV-04, SAV-06, SAV-T01).
# Usage : powershell -File scripts/restaurer.ps1 -Fichier C:/lyrics-vocab/sauvegardes/lyrics_vocab_2026-10-12.dump
param(
    [Parameter(Mandatory = $true)][string]$Fichier,
    [string]$Cible = "lyrics_vocab_restauree",
    [string]$Utilisateur = "postgres"
)
$ErrorActionPreference = "Stop"
$Debut = Get-Date
& createdb -U $Utilisateur -h 127.0.0.1 -E UTF8 $Cible
if ($LASTEXITCODE -ne 0) { throw "createdb a échoué (la base $Cible existe peut-être déjà)" }
& pg_restore -U $Utilisateur -h 127.0.0.1 -d $Cible --no-owner $Fichier
if ($LASTEXITCODE -ne 0) { throw "pg_restore a échoué" }
$Requete = "SELECT 'mot', count(*) FROM mot UNION ALL SELECT 'extrait', count(*) FROM extrait " +
           "UNION ALL SELECT 'revision', count(*) FROM revision UNION ALL SELECT 'artiste', count(*) FROM artiste " +
           "UNION ALL SELECT 'alembic', count(*) FROM alembic_version;"
Write-Host "Lignes par table dans $Cible (à comparer avec la base d'origine) :"
& psql -U $Utilisateur -h 127.0.0.1 -d $Cible -At -F " : " -c $Requete
Write-Host ("Restauration terminée en {0:N0} s." -f ((Get-Date) - $Debut).TotalSeconds)
Write-Host "Pour l'utiliser : arrêter le backend, renommer les bases, puis 'alembic upgrade head' et /api/health."
