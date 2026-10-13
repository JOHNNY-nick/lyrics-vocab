# Notification Windows d'un mot (fiche du mot au clic), lancée par le backend.
# Enregistre au besoin l'identité « Lyrics & Vocab » des notifications et le lien
# lyricsvocab://mot/<id>, qui ouvre la fiche dans l'application (Chrome --app).
param(
    [Parameter(Mandatory = $true)][string]$Titre,
    [string]$Texte = "",
    [Parameter(Mandatory = $true)][string]$MotId,
    [Parameter(Mandatory = $true)][string]$UrlApp,
    [string]$Icone = "C:/lyrics-vocab/icone/lyrics-vocab.png"
)

$Aumid = "LyricsVocab.Application"
$Cle = "HKCU:\Software\Classes\AppUserModelId\$Aumid"
if (-not (Test-Path $Cle)) { New-Item -Path $Cle -Force | Out-Null }
Set-ItemProperty -Path $Cle -Name DisplayName -Value "Lyrics & Vocab"
if (Test-Path $Icone) { Set-ItemProperty -Path $Cle -Name IconUri -Value $Icone }

# Lien lyricsvocab:// : un petit script ouvre la fiche sans fenêtre de console.
$Ouvrir = Join-Path $PSScriptRoot "ouvrir_mot.vbs"
$Protocole = "HKCU:\Software\Classes\lyricsvocab"
$Commande = "wscript.exe `"$Ouvrir`" `"%1`" `"$UrlApp`""
if ((Get-ItemProperty "$Protocole\shell\open\command" -ErrorAction SilentlyContinue).'(default)' -ne $Commande) {
    New-Item -Path "$Protocole\shell\open\command" -Force | Out-Null
    Set-ItemProperty -Path $Protocole -Name "(default)" -Value "URL:Lyrics & Vocab"
    Set-ItemProperty -Path $Protocole -Name "URL Protocol" -Value ""
    Set-ItemProperty -Path "$Protocole\shell\open\command" -Name "(default)" -Value $Commande
}

[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null

function Echapper([string]$s) { [System.Security.SecurityElement]::Escape($s) }
$Lien = "lyricsvocab://mot/$MotId"
$Xml = @"
<toast launch="$Lien" activationType="protocol">
  <visual><binding template="ToastGeneric">
    <text>$(Echapper $Titre)</text>
    <text>$(Echapper $Texte)</text>
  </binding></visual>
  <actions><action content="Voir la fiche" arguments="$Lien" activationType="protocol"/></actions>
</toast>
"@
$Document = New-Object Windows.Data.Xml.Dom.XmlDocument
$Document.LoadXml($Xml)
$Notification = [Windows.UI.Notifications.ToastNotification]::new($Document)
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($Aumid).Show($Notification)
