<#
.SYNOPSIS
    Installa il backup della sagra: file di configurazione, password
    del repository e attivita' pianificata ogni 10 minuti.

.DESCRIPTION
    Va eseguito come amministratore: l'attivita' pianificata deve
    girare con privilegi elevati perche' VSS li richiede.

.EXAMPLE
    .\Install-SagraBackup.ps1
    .\Install-SagraBackup.ps1 -IntervalloMinuti 5
#>

[CmdletBinding()]
param(
    [int]$IntervalloMinuti = 10,
    [string]$NomeAttivita  = 'Backup Sagra',

    # Cartella dati dell'applicazione. Passata dall'installer come {app};
    # se omessa resta quella del file di configurazione.
    [string]$SagraHome
)

$ErrorActionPreference = 'Stop'

$admin = ([Security.Principal.WindowsPrincipal] `
          [Security.Principal.WindowsIdentity]::GetCurrent()
         ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $admin) {
    Write-Host "ERRORE: esegui questo script come amministratore." -ForegroundColor Red
    Write-Host "(tasto destro su PowerShell -> 'Esegui come amministratore')" -ForegroundColor Yellow
    exit 1
}

$SrcDir  = $PSScriptRoot
$BaseDir = "$env:ProgramData\SagraBackup"
$Config  = Join-Path $BaseDir 'config.ps1'
$PwFile  = Join-Path $BaseDir 'restic-password.txt'
$Script  = Join-Path $BaseDir 'Invoke-SagraBackup.ps1'

function Write-Step { param([string]$m) Write-Host "`n== $m ==" -ForegroundColor Cyan }

# ------------------------------------------------------------------
# 1. Prerequisiti
# ------------------------------------------------------------------
Write-Step 'Verifica prerequisiti'

function Update-PathSessione {
    # ricarica il PATH dopo un'installazione, senza riaprire PowerShell
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')
}

function Find-Eseguibile {
    param([string]$Nome)

    $cmd = Get-Command $Nome -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    # winget installa alcuni pacchetti in modalita' "portable": l'alias
    # puo' mancare e l'eseguibile avere il nome versionato.
    $percorsi = @(
        "$env:LOCALAPPDATA\Microsoft\WinGet\Packages",
        "$env:LOCALAPPDATA\Microsoft\WinGet\Links",
        "$env:ProgramFiles\WinGet\Packages",
        "$env:ProgramFiles\WinGet\Links"
    ) | Where-Object { Test-Path $_ }

    foreach ($p in $percorsi) {
        $trovato = Get-ChildItem -Path $p -Filter "$Nome*.exe" -Recurse -ErrorAction SilentlyContinue |
                   Select-Object -First 1
        if ($trovato) { return $trovato.FullName }
    }
    return $null
}

function Install-ConWinget {
    param([string]$Nome, [string]$IdPacchetto)

    Write-Host "  $Nome non trovato: provo a installarlo con winget..." -ForegroundColor Yellow

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Host "  winget non disponibile su questo sistema." -ForegroundColor Red
        Write-Host "  Installa $Nome manualmente, poi riesegui questo script." -ForegroundColor Yellow
        return $null
    }

    # --scope Machine: installa in Program Files invece che nel profilo
    # utente, necessario perche' l'attivita' gira come SYSTEM
    & winget install --exact --id $IdPacchetto --scope Machine `
        --accept-source-agreements --accept-package-agreements --silent

    Update-PathSessione
    Start-Sleep -Seconds 2

    $exe = Find-Eseguibile $Nome
    if ($exe) {
        Write-Host "  $Nome installato: $exe" -ForegroundColor Green
    } else {
        Write-Host "  installazione di $Nome non riuscita o non rilevata." -ForegroundColor Red
    }
    return $exe
}

# --- restic (obbligatorio) ---
$resticExe = Find-Eseguibile 'restic'
if (-not $resticExe) {
    $resticExe = Install-ConWinget 'restic' 'restic.restic'
}
if (-not $resticExe) {
    Write-Host "ERRORE: restic non disponibile, impossibile proseguire." -ForegroundColor Red
    exit 1
}
Write-Host "restic: OK" -ForegroundColor Green

# --- rclone (solo per Dropbox) ---
$rcloneExe = Find-Eseguibile 'rclone'
if (-not $rcloneExe) {
    Write-Host ""
    $r = Read-Host "  rclone non trovato (serve solo per Dropbox). Installarlo? [S/n]"
    if ($r -notmatch '^[nN]') {
        $rcloneExe = Install-ConWinget 'rclone' 'Rclone.Rclone'
    }
}
if ($rcloneExe) {
    Write-Host "rclone: OK" -ForegroundColor Green
} else {
    Write-Host "rclone assente: il backup su Dropbox sara' disattivato." -ForegroundColor Yellow
}

# ------------------------------------------------------------------
# 2. Cartella, script, configurazione
# ------------------------------------------------------------------
Write-Step 'Installazione file'

New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null
Copy-Item (Join-Path $SrcDir 'Invoke-SagraBackup.ps1')  $Script -Force
Copy-Item (Join-Path $SrcDir 'Restore-SagraBackup.ps1') (Join-Path $BaseDir 'Restore-SagraBackup.ps1') -Force
Write-Host "  -> $BaseDir" -ForegroundColor Green

if (Test-Path $Config) {
    Write-Host "  config gia' presente: lasciata invariata" -ForegroundColor Yellow
} else {
    Copy-Item (Join-Path $SrcDir 'config.esempio.ps1') $Config -Force

    # registra i percorsi effettivi degli eseguibili trovati/installati
    # (sostituzione letterale, niente regex: i simboli $ non danno problemi)
    $testo = Get-Content $Config -Raw
    if ($SagraHome) {
        $testo = $testo.Replace("`$SagraHome = 'C:\SAGRA'", "`$SagraHome = '$SagraHome'")
    }
    $testo = $testo.Replace("`$ResticExe = ''", "`$ResticExe = '$resticExe'")
    if ($rcloneExe) {
        $testo = $testo.Replace("`$RcloneExe = ''", "`$RcloneExe = '$rcloneExe'")
    } else {
        $testo = $testo.Replace('$AbilitaCloud = $true', '$AbilitaCloud = $false')
    }
    Set-Content $Config $testo -Encoding UTF8

    Write-Host "  creata $Config  (da adattare!)" -ForegroundColor Green
}

# ------------------------------------------------------------------
# 3. Password del repository
# ------------------------------------------------------------------
Write-Step 'Password repository restic'

if (Test-Path $PwFile) {
    Write-Host "  password gia' presente" -ForegroundColor Yellow
} else {
    Write-Host "  ATTENZIONE: senza questa password i backup NON sono recuperabili." -ForegroundColor Yellow
    Write-Host "  Annotala anche altrove (es. gestore di password)." -ForegroundColor Yellow
    Write-Host ""

    $p1 = Read-Host "  Password" -AsSecureString
    $p2 = Read-Host "  Ripeti  " -AsSecureString

    $s1 = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($p1))
    $s2 = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($p2))

    if ($s1 -ne $s2 -or [string]::IsNullOrWhiteSpace($s1)) {
        Write-Host "  ERRORE: password vuota o non coincidente. Riesegui l'installazione." -ForegroundColor Red
        exit 1
    }

    # senza BOM: restic legge il file cosi' com'e'
    [IO.File]::WriteAllText($PwFile, $s1, (New-Object Text.UTF8Encoding $false))

    # accesso limitato a SYSTEM e Administrators
    $acl = Get-Acl $PwFile
    $acl.SetAccessRuleProtection($true, $false)
    $acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) | Out-Null }
    foreach ($id in 'NT AUTHORITY\SYSTEM', 'BUILTIN\Administrators') {
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule(
            $id, 'FullControl', 'Allow')))
    }
    Set-Acl $PwFile $acl

    $s1 = $null; $s2 = $null
    Write-Host "  salvata in $PwFile (accesso limitato)" -ForegroundColor Green
}

# ------------------------------------------------------------------
# 3b. Controllo della chiavetta di backup
# ------------------------------------------------------------------
Write-Step 'Chiavetta di backup'

$EtichettaAttesa = 'BACKUP_SAGRA'

Write-Host "  La chiavetta usata per i backup deve avere etichetta di volume:" -ForegroundColor White
Write-Host "      $EtichettaAttesa" -ForegroundColor Cyan
Write-Host "  E' cosi' che il backup la riconosce, qualunque lettera di unita'" -ForegroundColor Gray
Write-Host "  le venga assegnata dal sistema." -ForegroundColor Gray
Write-Host ""

$rimovibili = Get-Volume -ErrorAction SilentlyContinue |
              Where-Object { $_.DriveType -eq 'Removable' -and $_.DriveLetter }

if (-not $rimovibili) {
    Write-Host "  Nessuna chiavetta inserita in questo momento." -ForegroundColor Yellow
    Write-Host "  Ricordati di prepararne una con etichetta '$EtichettaAttesa'" -ForegroundColor Yellow
    Write-Host "  prima della sagra, altrimenti restera' attivo solo il backup su Dropbox." -ForegroundColor Yellow
}
elseif ($rimovibili | Where-Object { $_.FileSystemLabel -eq $EtichettaAttesa }) {
    $ok = $rimovibili | Where-Object { $_.FileSystemLabel -eq $EtichettaAttesa } | Select-Object -First 1
    Write-Host "  Trovata: unita' $($ok.DriveLetter): con etichetta corretta." -ForegroundColor Green
}
else {
    Write-Host "  Chiavette inserite, ma nessuna con l'etichetta richiesta:" -ForegroundColor Yellow
    foreach ($v in $rimovibili) {
        $et = if ($v.FileSystemLabel) { $v.FileSystemLabel } else { '(senza etichetta)' }
        Write-Host ("    {0}:  {1}" -f $v.DriveLetter, $et)
    }
    Write-Host ""

    if ($rimovibili.Count -eq 1) {
        $v = $rimovibili[0]
        Write-Host "  Posso rinominare l'unita' $($v.DriveLetter): in '$EtichettaAttesa'." -ForegroundColor White
        Write-Host "  La rinomina NON cancella i dati presenti sulla chiavetta." -ForegroundColor Gray
        $r = Read-Host "  Procedo con la rinomina? [S/n]"
        if ($r -notmatch '^[nN]') {
            try {
                Set-Volume -DriveLetter $v.DriveLetter -NewFileSystemLabel $EtichettaAttesa -ErrorAction Stop
                Write-Host "  Etichetta impostata su '$EtichettaAttesa'." -ForegroundColor Green
            } catch {
                Write-Host "  Rinomina non riuscita: $($_.Exception.Message)" -ForegroundColor Red
                Write-Host "  Puoi farlo a mano: Esplora file -> tasto destro sulla chiavetta -> Rinomina," -ForegroundColor Yellow
                Write-Host "  oppure formattarla indicando '$EtichettaAttesa' come nome del volume." -ForegroundColor Yellow
            }
        } else {
            Write-Host "  Saltato. Ricordati di rinominarla o formattarla con etichetta '$EtichettaAttesa'." -ForegroundColor Yellow
        }
    } else {
        Write-Host "  Ci sono piu' unita' rimovibili: non rinomino nulla per sicurezza." -ForegroundColor Yellow
        Write-Host "  Rinomina a mano quella giusta in '$EtichettaAttesa'" -ForegroundColor Yellow
        Write-Host "  (Esplora file -> tasto destro -> Rinomina), oppure formattala" -ForegroundColor Yellow
        Write-Host "  indicando '$EtichettaAttesa' come nome del volume." -ForegroundColor Yellow
    }
}

# ------------------------------------------------------------------
# 4. Attivita' pianificata
# ------------------------------------------------------------------
Write-Step "Attivita' pianificata (ogni $IntervalloMinuti minuti)"

if (Get-ScheduledTask -TaskName $NomeAttivita -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $NomeAttivita -Confirm:$false
    Write-Host "  attivita' precedente rimossa"
}

$azione = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Script`""

$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).Date `
    -RepetitionInterval (New-TimeSpan -Minutes $IntervalloMinuti)

$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' `
    -LogonType ServiceAccount -RunLevel Highest

$impostazioni = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 30)

Register-ScheduledTask -TaskName $NomeAttivita -Action $azione `
    -Trigger $trigger -Principal $principal -Settings $impostazioni `
    -Description 'Backup dati sagra con restic verso chiavetta USB e Dropbox' | Out-Null

Write-Host "  attivita' '$NomeAttivita' creata" -ForegroundColor Green

# ------------------------------------------------------------------
Write-Host @"

============================================
Installazione completata.

PROSSIMI PASSI
  1. Adatta la configurazione:
       notepad "$Config"
     in particolare SagraHome e EtichettaUSB.

  2. Per Dropbox, configura rclone una volta sola:
       rclone config
     crea un remote di tipo 'dropbox' chiamato 'dropbox'.

     NOTA: l'attivita' gira come SYSTEM, che ha una configurazione
     rclone diversa dalla tua. Copia il file di configurazione:
       copy "%APPDATA%\rclone\rclone.conf" "C:\Windows\System32\config\systemprofile\AppData\Roaming\rclone\"
     oppure imposta l'attivita' per girare col tuo utente.

  3. Prova subito un backup:
       Start-ScheduledTask -TaskName "$NomeAttivita"
       Get-Content "$env:ProgramData\SagraBackup\backup.log" -Tail 20 -Wait

COMANDI UTILI
  Get-ScheduledTask -TaskName "$NomeAttivita" | Get-ScheduledTaskInfo
  & "$BaseDir\Restore-SagraBackup.ps1" -Azione elenco
  & "$BaseDir\Restore-SagraBackup.ps1" -Azione ripristina -Snapshot latest
============================================
"@ -ForegroundColor White
