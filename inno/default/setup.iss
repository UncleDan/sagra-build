; ============================================================
; Setup - Gestione Stand Gastronomico (versione DEFAULT)
; Installa i runtime VB6/OCX necessari + l'applicazione principale
; Sorgente app: C:\SAGRA
; ============================================================

#define MyAppName "Gestione Stand Gastronomico"
#define MyAppVersion "3.4.0"
#define MyAppExeName "Sagra3.4.0.exe"
#define MyReportName "report-sagra.html"
#define MySourceDir "C:\SAGRA"

[Setup]
AppName={#MyAppName}
AppVersion={#MyAppVersion}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
; dist relativa alla posizione di questo .iss, cosi' l'output
; e' sempre in dist\ ovunque sia collocato il progetto
OutputDir=dist
OutputBaseFilename=Sagra3.4.0_setup
Compression=lzma
SolidCompression=yes
; Richiede privilegi amministrativi: necessario per registrare le OCX
; in {sys} e per creare l'icona sul desktop "per tutti gli utenti"
PrivilegesRequired=admin
; NON impostare ArchitecturesInstallIn64BitMode: l'app è VB6 a 32 bit,
; deve restare un installer a 32 bit cosi' {sys} punta a SysWOW64
; su Windows 64 bit (dove l'app 32 bit si aspetta di trovare le OCX/DLL)

[Languages]
Name: "italian"; MessagesFile: "compiler:Languages\Italian.isl"

[Tasks]
Name: "backup"; Description: "Installa il backup automatico (restic + VSS, ogni 10 minuti)"; GroupDescription: "Opzioni aggiuntive:"; Flags: unchecked

[Files]
; --- Runtime e controlli VB6 (estratti dall'installer originale) ---
Source: "sys\*"; DestDir: "{sys}"; Flags: regserver sharedfile restartreplace uninsneveruninstall

; --- File informativi originali ---
Source: "app\ReadMe.txt"; DestDir: "{app}"; Flags: isreadme

; --- Script di backup (restic + VSS) ---
Source: "backup\*"; DestDir: "{app}\backup"; Flags: ignoreversion recursesubdirs createallsubdirs; Tasks: backup

; --- Applicazione principale ---
Source: "{#MySourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
; Voce nel menu Start
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Disinstalla {#MyAppName}"; Filename: "{uninstallexe}"

; Icona sul Desktop visibile a TUTTI gli utenti ({commondesktop})
Name: "{commondesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"

; Collegamenti al report HTML, creati solo se il file e' stato installato
Name: "{group}\Report Sagra"; Filename: "{app}\{#MyReportName}"; Check: ReportPresente
Name: "{commondesktop}\Report Sagra"; Filename: "{app}\{#MyReportName}"; Check: ReportPresente

[Run]
; Configurazione del backup: gira elevato, serve per VSS e Utilita' di pianificazione
Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\backup\Install-SagraBackup.ps1"""; \
  StatusMsg: "Configurazione del backup automatico..."; \
  Flags: waituntilterminated; Tasks: backup

Filename: "{app}\{#MyAppExeName}"; Description: "Avvia {#MyAppName}"; Flags: nowait postinstall skipifsilent

[Code]
// Vero se il report HTML e' stato installato assieme all'applicazione:
// i collegamenti relativi vengono creati solo in quel caso.
function ReportPresente: Boolean;
begin
  Result := FileExists(ExpandConstant('{app}\{#MyReportName}'));
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usPostUninstall then
  begin
    if MsgBox('Vuoi eliminare anche la cartella dell''applicazione e tutti i dati residui (' + ExpandConstant('{app}') + ')?', mbConfirmation, MB_YESNO) = IDYES then
    begin
      DelTree(ExpandConstant('{app}'), True, True, True);
    end;
  end;
end;
