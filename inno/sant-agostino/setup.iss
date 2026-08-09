; ============================================================
; Setup - Gestione Stand Gastronomico (versione SAGRA_SANT-AGOSTINO)
; Installa i runtime VB6/OCX necessari + l'applicazione principale
; Sorgente app: C:\SAGRA_SANT-AGOSTINO
; ============================================================

#define MyAppName "Gestione Stand Gastronomico - Sant'Agostino"
#define MyAppVersion "3.4.0"
#define MyAppExeName "Sagra3.4.0.exe"
#define MyReportName "report-sagra.html"
#define MySourceDir "C:\SAGRA_SANT-AGOSTINO"
; Timestamp di generazione dell'installer (data/ora di compilazione)
#define TimeStamp GetDateTimeString('yyyymmdd_hhnnss', '', '')

[Setup]
AppName={#MyAppName}
AppVersion={#MyAppVersion}
; Installazione nella radice del disco di sistema ({sd} = di norma C:),
; NON in Program Files: l'applicazione VB6 scrive i propri dati
; accanto a se' stessa e cerca i file con percorsi assoluti.
DefaultDirName={sd}\SAGRA_SANT-AGOSTINO
; disattiva l'avviso standard di Inno: ne usiamo uno piu' esplicito
DirExistsWarning=no
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
; dist relativa alla posizione di questo .iss, cosi' l'output
; e' sempre in dist\ ovunque sia collocato il progetto
OutputDir=dist
OutputBaseFilename=SAGRA_SANT-AGOSTINO_setup_{#TimeStamp}
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

; --- Applicazione principale (versione personalizzata Sant'Agostino) ---
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
  Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\backup\Install-SagraBackup.ps1"" -SagraHome ""{app}"""; \
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

// ------------------------------------------------------------------
// Avviso se la cartella di destinazione esiste gia'.
// Distingue una cartella vuota (innocua) da una che contiene gia'
// un'installazione con dati: in quel caso l'avviso e' esplicito.
// ------------------------------------------------------------------
function NextButtonClick(CurPageID: Integer): Boolean;
var
  Percorso, Messaggio: String;
  FR: TFindRec;
  HaFile, HaDati: Boolean;
begin
  Result := True;
  if CurPageID <> wpSelectDir then
    Exit;

  Percorso := WizardDirValue;
  if not DirExists(Percorso) then
    Exit;

  HaFile := False;
  HaDati := False;

  if FindFirst(Percorso + '\*', FR) then
  begin
    try
      repeat
        if (FR.Name <> '.') and (FR.Name <> '..') then
        begin
          HaFile := True;
          // estensioni tipiche dei dati dell'applicazione
          if (Pos('.mdb', Lowercase(FR.Name)) > 0) or
             (Pos('.accdb', Lowercase(FR.Name)) > 0) or
             (Pos('.ini', Lowercase(FR.Name)) > 0) then
            HaDati := True;
        end;
      until not FindNext(FR);
    finally
      FindClose(FR);
    end;
  end;

  if not HaFile then
    Exit;

  if HaDati then
  begin
    Messaggio :=
      'La cartella' + #13#10#13#10 +
      Percorso + #13#10#13#10 +
      'esiste gia'' e contiene quelli che sembrano dati di ' +
      'un''installazione precedente (database e/o file di configurazione).' + #13#10#13#10 +
      'Proseguendo, il programma e le librerie verranno aggiornati. ' +
      'I file di dati esistenti NON vengono eliminati dal setup, ma ' +
      'eventuali file con lo stesso nome inclusi nell''installer ' +
      'potrebbero sovrascriverli.' + #13#10#13#10 +
      'Si consiglia vivamente di fare una copia di sicurezza della ' +
      'cartella prima di continuare.' + #13#10#13#10 +
      'Vuoi procedere comunque?';
  end
  else
  begin
    Messaggio :=
      'La cartella' + #13#10#13#10 +
      Percorso + #13#10#13#10 +
      'esiste gia'' e contiene dei file.' + #13#10#13#10 +
      'Vuoi installare comunque in questa cartella?';
  end;

  Result := MsgBox(Messaggio, mbConfirmation, MB_YESNO) = IDYES;
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
