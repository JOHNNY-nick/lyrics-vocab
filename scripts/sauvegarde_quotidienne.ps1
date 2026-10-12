# Sauvegarde quotidienne de la base (K.2, SAV-01 à SAV-05, 31.5).
# Aucun mot de passe ici (CMD-02) : la connexion utilise un fichier pgpass
# (C:/lyrics-vocab/secrets/pgpass.conf s'il existe, sinon %APPDATA%\postgresql\pgpass.conf).
param(
    [string]$Racine = "C:/lyrics-vocab",
    # Copie hors du PC (SAV-02) : dossier OneDrive s'il existe, sinon un autre disque.
    [string]$Copie = $(if ($env:OneDrive) { "$env:OneDrive/lyrics-vocab-sauvegardes" } else { "D:/copie-lyrics-vocab" }),
    [string]$Base = "lyrics_vocab",
    [string]$Utilisateur = "postgres",
    [int]$Retention = 14
)
$ErrorActionPreference = "Stop"
if (Test-Path "$Racine/secrets/pgpass.conf") { $env:PGPASSFILE = "$Racine/secrets/pgpass.conf" }
if (Test-Path "$Racine/postgresql/bin/pg_dump.exe") { $env:PATH = "$Racine/postgresql/bin;$env:PATH" }
$Dossier = "$Racine/sauvegardes"
$Journal = "$Racine/logs/sauvegarde.log"
New-Item -ItemType Directory -Force $Dossier, "$Racine/logs" | Out-Null
$Date = Get-Date -Format "yyyy-MM-dd"
$Cible = "$Dossier/lyrics_vocab_$Date.dump"
$Debut = Get-Date

function Ecrire-Journal([string]$Resultat, [string]$Detail) {
    $Ligne = @{ horodatage = (Get-Date).ToUniversalTime().ToString("o"); evenement = "sauvegarde";
                niveau = $(if ($Resultat -eq "OK") { "info" } else { "erreur" });
                fichier = $Cible; resultat = $Resultat; detail = $Detail;
                duree_ms = [int]((Get-Date) - $Debut).TotalMilliseconds } | ConvertTo-Json -Compress
    Add-Content -Path $Journal -Value $Ligne -Encoding utf8
}

try {
    & pg_dump -Fc -U $Utilisateur -h 127.0.0.1 -f $Cible $Base
    if ($LASTEXITCODE -ne 0) { throw "pg_dump a échoué (code $LASTEXITCODE)" }
    $Taille = (Get-Item $Cible).Length
    if ($Taille -lt 1024) { throw "fichier de sauvegarde anormalement petit ($Taille octets)" }
    if (Test-Path (Split-Path $Copie -Qualifier)) {
        New-Item -ItemType Directory -Force $Copie | Out-Null
        Copy-Item $Cible $Copie -Force
    } else {
        Ecrire-Journal "AVERTISSEMENT" "copie impossible : $Copie absent"
    }
    Get-ChildItem $Dossier -Filter *.dump |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$Retention) } | Remove-Item
    Ecrire-Journal "OK" "taille=$Taille"
    # Marqueur lu par le script de contrôle : date de la dernière sauvegarde réussie.
    Set-Content -Path "$Dossier/derniere_reussie.txt" -Value $Date -Encoding utf8
} catch {
    Ecrire-Journal "ECHEC" $_.Exception.Message
    exit 1
}
