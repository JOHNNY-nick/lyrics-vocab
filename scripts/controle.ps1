# Script de contrôle (ENV-12, OBS-02, SQL-04) : état de PostgreSQL, Ollama, backend, Tailscale,
# sauvegarde et intégrité de la base. Usage : powershell -File scripts/controle.ps1
param(
    [string]$Racine = "C:/lyrics-vocab",
    [string]$Base = "lyrics_vocab",
    [string]$Utilisateur = "postgres"
)
$RacineInstall = $Racine
if (Test-Path "$RacineInstall/secrets/pgpass.conf") { $env:PGPASSFILE = "$RacineInstall/secrets/pgpass.conf" }
if (Test-Path "$RacineInstall/postgresql/bin/psql.exe") { $env:PATH = "$RacineInstall/postgresql/bin;$env:PATH" }

function Etat([string]$Nom, [bool]$Ok, [string]$Detail = "") {
    $Marque = if ($Ok) { "[ OK ]" } else { "[ KO ]" }
    $Couleur = if ($Ok) { "Green" } else { "Red" }
    Write-Host ("{0} {1,-12} {2}" -f $Marque, $Nom, $Detail) -ForegroundColor $Couleur
}

function Port-Ouvert([int]$Port) {
    try { (New-Object Net.Sockets.TcpClient("127.0.0.1", $Port)).Close(); return $true } catch { return $false }
}

Etat "PostgreSQL" (Port-Ouvert 5432) "127.0.0.1:5432"

try {
    $Tags = Invoke-RestMethod "http://127.0.0.1:11434/api/tags" -TimeoutSec 3
    $Modeles = ($Tags.models | ForEach-Object { $_.name }) -join ", "
    Etat "Ollama" $true $Modeles
} catch { Etat "Ollama" $false "arrêté ou injoignable (facultatif)" }

try {
    $Sante = Invoke-RestMethod "http://127.0.0.1:8000/api/health" -TimeoutSec 3
    Etat "Backend" ($Sante.status -eq "ok") ("version {0}, base {1}, curseur {2}" -f $Sante.version, $Sante.base, $Sante.curseur)
} catch { Etat "Backend" $false "ne répond pas sur 127.0.0.1:8000 (voir $Racine/logs/uvicorn.log)" }

try {
    $Statut = & tailscale status --json 2>$null | ConvertFrom-Json
    Etat "Tailscale" ($Statut.BackendState -eq "Running") ("{0} — {1}" -f $Statut.BackendState, $Statut.Self.DNSName)
    $Serve = & tailscale serve status 2>$null
    Etat "Serve" ([bool]($Serve -match "8000")) (($Serve | Select-Object -First 1) -join "")
} catch { Etat "Tailscale" $false "commande tailscale introuvable" }

$Marqueur = "$Racine/sauvegardes/derniere_reussie.txt"
if (Test-Path $Marqueur) {
    $Derniere = [datetime]::ParseExact((Get-Content $Marqueur).Trim(), "yyyy-MM-dd", $null)
    $Age = ((Get-Date) - $Derniere).TotalHours
    Etat "Sauvegarde" ($Age -lt 48) ("dernière réussie le {0:yyyy-MM-dd}" -f $Derniere)
} else { Etat "Sauvegarde" $false "aucune sauvegarde réussie trouvée (SAV-T02)" }

# Contrôle d'intégrité (SQL-04) : extraits sans mot, révisions planifiées multiples.
$Requete = @"
SELECT 'extraits_orphelins', count(*) FROM extrait e LEFT JOIN mot m ON m.id = e.mot_id
  WHERE e.deleted_at IS NULL AND (m.id IS NULL OR m.deleted_at IS NOT NULL)
UNION ALL
SELECT 'planifiees_multiples', count(*) FROM (SELECT mot_id FROM revision
  WHERE statut = 'planifiee' AND deleted_at IS NULL GROUP BY mot_id HAVING count(*) > 1) x
UNION ALL
SELECT 'mots_sans_planifiee', count(*) FROM mot m WHERE m.deleted_at IS NULL AND NOT EXISTS
  (SELECT 1 FROM revision r WHERE r.mot_id = m.id AND r.statut = 'planifiee' AND r.deleted_at IS NULL);
"@
try {
    $Lignes = & psql -U $Utilisateur -h 127.0.0.1 -d $Base -At -F "=" -c $Requete 2>$null
    foreach ($Ligne in $Lignes) {
        $Nom, $Nombre = $Ligne.Split("=")
        Etat "Intégrité" ([int]$Nombre -eq 0) "$Nom : $Nombre"
    }
} catch { Etat "Intégrité" $false "psql introuvable dans le PATH" }
