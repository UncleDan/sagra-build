; ============================================================
; Setup - Gestione Stand Gastronomico (versione DEFAULT)
; Installa i runtime VB6/OCX necessari + l'applicazione principale
; Sorgente app: C:\SAGRA
; ============================================================

#define MyAppName "Gestione Stand Gastronomico"
#define MyAppVersion "3.4.0"
#define MyAppExeName "Sagra3.4.0.exe"
#define MySourceDir "C:\SAGRA"

[Setup]
AppName={#MyAppName}
AppVersion={#MyAppVersion}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
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

[Files]
; --- Runtime e controlli VB6 (estratti dall'installer originale) ---
Source: "sys\*"; DestDir: "{sys}"; Flags: regserver sharedfile restartreplace uninsneveruninstall

; --- File informativi originali ---
Source: "app\ReadMe.txt"; DestDir: "{app}"; Flags: isreadme

; --- Applicazione principale ---
Source: "{#MySourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
; Voce nel menu Start
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Disinstalla {#MyAppName}"; Filename: "{uninstallexe}"

; Icona sul Desktop visibile a TUTTI gli utenti ({commondesktop})
Name: "{commondesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Avvia {#MyAppName}"; Flags: nowait postinstall skipifsilent

[Code]
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
