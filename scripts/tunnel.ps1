# Tunnel Cloudflare gratuit (trycloudflare) vers le backend, pour les amis sans Tailscale.
# L'adresse change à chaque démarrage : elle est publiée sur la branche « adresse » du dépôt
# GitHub (adresse.json), que l'application mobile lit quand le PC ne répond plus.
# Lancé par la tâche planifiée « Lyrics Vocab Tunnel » à l'ouverture de session.
param(
    [string]$Racine = "C:/lyrics-vocab",
    [string]$Depot = "JOHNNY-nick/lyrics-vocab"
)

$Exe = "$Racine/outils/cloudflared/cloudflared.exe"
$Gh = "$Racine/outils/gh/bin/gh.exe"
$Journaux = "$Racine/logs"
$Sortie = "$Journaux/cloudflared.log"
New-Item -ItemType Directory -Force $Journaux, "$Racine/tunnel" | Out-Null

function Journal([string]$Message) {
    Add-Content -Path "$Journaux/tunnel.log" -Encoding utf8 `
        -Value ("{0} {1}" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"), $Message)
}

function Publier([string]$Url) {
    Set-Content -Path "$Racine/tunnel/adresse.txt" -Value $Url -Encoding ascii
    $Contenu = @{ adresse = $Url; maj = (Get-Date).ToUniversalTime().ToString("o") } | ConvertTo-Json -Compress
    $Base64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Contenu))
    for ($Essai = 1; $Essai -le 5; $Essai++) {
        $Sha = & $Gh api "repos/$Depot/contents/adresse.json?ref=adresse" --jq .sha 2>$null
        & $Gh api -X PUT "repos/$Depot/contents/adresse.json" -f message="adresse du serveur" `
            -f content=$Base64 -f branch=adresse -f sha=$Sha *> $null
        if ($LASTEXITCODE -eq 0) { Journal "adresse publiée : $Url"; return }
        Start-Sleep -Seconds (10 * $Essai)
    }
    Journal "publication de l'adresse impossible (GitHub)"
}

while ($true) {
    Remove-Item $Sortie -ErrorAction SilentlyContinue
    Journal "démarrage du tunnel"
    $Processus = Start-Process -FilePath $Exe -WindowStyle Hidden -PassThru `
        -ArgumentList @("tunnel", "--no-autoupdate", "--url", "http://127.0.0.1:8000") `
        -RedirectStandardError $Sortie
    $Url = $null
    for ($i = 0; $i -lt 90 -and -not $Url -and -not $Processus.HasExited; $i++) {
        Start-Sleep -Seconds 1
        $Trouve = Select-String -Path $Sortie -Pattern "https://[a-z0-9-]+\.trycloudflare\.com" -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($Trouve) { $Url = $Trouve.Matches[0].Value }
    }
    if ($Url) { Publier $Url } else { Journal "adresse du tunnel introuvable" }
    $Processus.WaitForExit()
    Journal "arrêt du tunnel (code $($Processus.ExitCode)), nouvelle tentative dans 30 s"
    Start-Sleep -Seconds 30
}
