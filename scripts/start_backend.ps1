# Démarrage de PostgreSQL puis du backend (A.5, ENV-02, ENV-03, ENV-11).
# Lancé par la tâche planifiée « Lyrics Vocab Backend ». Le backend écoute uniquement sur
# 127.0.0.1 (ENV-01) ; tailscale serve l'expose dans le tailnet.
param([string]$Racine = "C:/lyrics-vocab")

$Pg = "$Racine/postgresql/bin"
$Donnees = "$Racine/pgdata"
$Journaux = "$Racine/logs"
New-Item -ItemType Directory -Force $Journaux | Out-Null

function Journal([string]$Message) {
    Add-Content -Path "$Journaux/demarrage.log" -Encoding utf8 `
        -Value ("{0} {1}" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"), $Message)
}

# PostgreSQL embarqué (installation sans service Windows, voir DECISIONS.md).
if (Test-Path "$Pg/pg_ctl.exe") {
    & "$Pg/pg_isready.exe" -h 127.0.0.1 -p 5432 -q
    if ($LASTEXITCODE -ne 0) {
        Journal "démarrage de PostgreSQL"
        Start-Process -FilePath "$Pg/pg_ctl.exe" -WindowStyle Hidden `
            -ArgumentList @("-D", "`"$Donnees`"", "-l", "`"$Journaux/pg_ctl.log`"", "start")
        for ($i = 0; $i -lt 30; $i++) {
            Start-Sleep -Seconds 2
            & "$Pg/pg_isready.exe" -h 127.0.0.1 -p 5432 -q
            if ($LASTEXITCODE -eq 0) { break }
        }
    }
}

# Le backend attend lui-même la base pendant 60 s ; il est relancé une minute après un arrêt.
Set-Location "$Racine/depot/backend"
while ($true) {
    Journal "démarrage du backend"
    & "$Racine/depot/backend/.venv/Scripts/python.exe" -m uvicorn app.main:app `
        --host 127.0.0.1 --port 8000 *>> "$Journaux/uvicorn.log"
    Journal "arrêt du backend (code $LASTEXITCODE), nouvelle tentative dans 60 s"
    Start-Sleep -Seconds 60
}
