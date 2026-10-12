# Crée les tâches planifiées (ENV-02, ENV-11, SAV-01). À lancer une fois, en administrateur.
# - « Lyrics Vocab Backend » : au démarrage du PC, même sans session ouverte,
#   3 redémarrages en cas d'échec, un par minute.
# - « Lyrics Vocab Sauvegarde » : chaque jour à l'heure choisie, rattrapée au démarrage si manquée.
param(
    [string]$Racine = "C:/lyrics-vocab",
    [string]$HeureSauvegarde = "21:00",
    [Parameter(Mandatory = $true)][string]$Compte   # ex. "MONPC\moi" : le compte qui lit le .env
)
$ErrorActionPreference = "Stop"
$Parametres = New-ScheduledTaskSettingsSet -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) `
    -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero)
$Mdp = Read-Host "Mot de passe Windows de $Compte (exécution sans session ouverte)" -AsSecureString
$Clair = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($Mdp))

$Action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-ExecutionPolicy Bypass -NoProfile -File $Racine/depot/scripts/start_backend.ps1"
Register-ScheduledTask -TaskName "Lyrics Vocab Backend" -Action $Action `
    -Trigger (New-ScheduledTaskTrigger -AtStartup) -Settings $Parametres `
    -User $Compte -Password $Clair -RunLevel Limited -Force | Out-Null

$ActionSauvegarde = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-ExecutionPolicy Bypass -NoProfile -File $Racine/depot/scripts/sauvegarde_quotidienne.ps1"
Register-ScheduledTask -TaskName "Lyrics Vocab Sauvegarde" -Action $ActionSauvegarde `
    -Trigger (New-ScheduledTaskTrigger -Daily -At $HeureSauvegarde) -Settings $Parametres `
    -User $Compte -Password $Clair -RunLevel Limited -Force | Out-Null

Write-Host "Tâches créées. Vérification : Get-ScheduledTask -TaskName 'Lyrics Vocab*'"
