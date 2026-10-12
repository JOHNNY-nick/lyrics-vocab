# Crée les tâches planifiées (ENV-02, ENV-11, SAV-01).
# - « Lyrics Vocab Backend » : PostgreSQL puis le backend, fenêtre masquée, relancé s'il s'arrête.
# - « Lyrics Vocab Sauvegarde » : chaque jour à l'heure choisie, rattrapée si l'heure est manquée.
# Sans droits administrateur (par défaut) : démarrage à l'ouverture de la session Windows.
# Avec -AuDemarrage (console administrateur) : démarrage avec Windows, même sans session ouverte ;
# le mot de passe Windows est alors demandé une fois.
param(
    [string]$Racine = "C:/lyrics-vocab",
    [string]$HeureSauvegarde = "21:00",
    [switch]$AuDemarrage
)
$ErrorActionPreference = "Stop"
$Utilisateur = "$env:USERDOMAIN\$env:USERNAME"
$Parametres = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew

function Action([string]$Script) {
    New-ScheduledTaskAction -Execute "powershell.exe" `
        -Argument "-ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File `"$Racine/depot/scripts/$Script`""
}

if ($AuDemarrage) {
    $Mdp = Read-Host "Mot de passe Windows de $Utilisateur" -AsSecureString
    $Clair = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Mdp))
    $Declencheur = New-ScheduledTaskTrigger -AtStartup
    Register-ScheduledTask -TaskName "Lyrics Vocab Backend" -Action (Action "start_backend.ps1") `
        -Trigger $Declencheur -Settings $Parametres -User $Utilisateur -Password $Clair -Force | Out-Null
    Register-ScheduledTask -TaskName "Lyrics Vocab Sauvegarde" -Action (Action "sauvegarde_quotidienne.ps1") `
        -Trigger (New-ScheduledTaskTrigger -Daily -At $HeureSauvegarde) -Settings $Parametres `
        -User $Utilisateur -Password $Clair -Force | Out-Null
} else {
    $Principal = New-ScheduledTaskPrincipal -UserId $Utilisateur -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName "Lyrics Vocab Backend" -Action (Action "start_backend.ps1") `
        -Trigger (New-ScheduledTaskTrigger -AtLogOn -User $Utilisateur) -Settings $Parametres `
        -Principal $Principal -Force | Out-Null
    Register-ScheduledTask -TaskName "Lyrics Vocab Sauvegarde" -Action (Action "sauvegarde_quotidienne.ps1") `
        -Trigger (New-ScheduledTaskTrigger -Daily -At $HeureSauvegarde) -Settings $Parametres `
        -Principal $Principal -Force | Out-Null
}
Get-ScheduledTask -TaskName "Lyrics Vocab*" | Format-Table TaskName, State
