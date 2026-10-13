' Ouvre la fiche d'un mot dans l'application PC depuis une notification Windows.
' Arguments : lien lyricsvocab://mot/<id>, adresse de l'application.
Dim lien, url, id, chrome
lien = WScript.Arguments(0)
url = WScript.Arguments(1)
id = Mid(lien, InStrRev(lien, "/") + 1)
' Seuls les identifiants (UUID) sont acceptés.
Set motif = New RegExp
motif.Pattern = "^[0-9a-fA-F-]{36}$"
If Not motif.Test(id) Then WScript.Quit 1
chrome = CreateObject("WScript.Shell").ExpandEnvironmentStrings("%ProgramFiles%") & "\Google\Chrome\Application\chrome.exe"
CreateObject("WScript.Shell").Run """" & chrome & """ --app=""" & url & "?mot=" & id & """", 1, False
