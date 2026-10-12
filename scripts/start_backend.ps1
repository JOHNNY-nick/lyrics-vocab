# Démarrage du backend (A.5). Lancé par le Planificateur de tâches au démarrage du PC.
# Écoute uniquement sur 127.0.0.1 (ENV-01) ; tailscale serve l'expose dans le tailnet.
$ErrorActionPreference = "Stop"
$Racine = "C:/lyrics-vocab"
Set-Location "$Racine/depot/backend"
New-Item -ItemType Directory -Force "$Racine/logs" | Out-Null
& "$Racine/depot/backend/.venv/Scripts/python.exe" -m uvicorn app.main:app --host 127.0.0.1 --port 8000 *>> "$Racine/logs/uvicorn.log"
exit $LASTEXITCODE
