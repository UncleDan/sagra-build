<#
.SYNOPSIS
    Backup incrementale della cartella dati della sagra con restic,
    verso due repository indipendenti (chiavetta USB e Dropbox).

.DESCRIPTION
    Usa il supporto VSS nativo di restic (--use-fs-snapshot): i file
    vengono letti da uno snapshot Volume Shadow Copy, quindi anche il
    database aperto in esclusiva dall'applicazione viene copiato senza
    interromperla e senza copie a metà scrittura.

    I due repository sono indipendenti: se la chiavetta non è inserita
    o manca la rete, l'altro backup viene comunque completato.

    Richiede privilegi amministrativi (necessari per VSS).

.EXAMPLE
    .\Invoke-SagraBackup.ps1
    .\Invoke-SagraBackup.ps1 -Config "D:\altro-config.ps1"
#>

[CmdletBinding()]
param(
    [string]$Config = "$env:ProgramData\SagraBackup\config.ps1"
)

$ErrorActionPreference = 'Continue'

if (-not (Test-Path $Config)) {
    Write-Error "Configurazione non trovata: $Config"
    exit 1
}
. $Config

$StateDir = Split-Path $LogFile -Parent
if (-not (Test-Path $StateDir)) { New-Item -ItemType Directory -Path $StateDir -Force | Out-Null }

# ------------------------------------------------------------------
# Log
# ------------------------------------------------------------------
function Write-Log {
    param([string]$Messaggio)
    $riga = "{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Messaggio
    Add-Content -Path $LogFile -Value $riga -Encoding UTF8
    Write-Verbose $riga
}

if (Test-Path $LogFile) {
    if ((Get-Item $LogFile).Length / 1KB -gt $LogMaxKB) {
        Move-Item $LogFile "$LogFile.1" -Force
        Write-Log "(log ruotato)"
    }
}

# ------------------------------------------------------------------
# Un'esecuzione alla volta
# ------------------------------------------------------------------
$mutex = New-Object System.Threading.Mutex($false, 'Global\SagraBackupMutex')
if (-not $mutex.WaitOne(0)) {
    Write-Log "SALTATO: un backup precedente e' ancora in corso"
    exit 0
}

try {
    # --------------------------------------------------------------
    # Prerequisiti
    # --------------------------------------------------------------
    # usa il percorso registrato dall'installer, altrimenti cerca nel PATH
    $Restic = if ($ResticExe -and (Test-Path $ResticExe)) { $ResticExe } else { 'restic' }
    if (-not (Get-Command $Restic -ErrorAction SilentlyContinue)) {
        Write-Log "ERRORE: restic non trovato (ne' in `$ResticExe ne' nel PATH)"
        exit 1
    }
    if (-not (Test-Path $SagraHome)) {
        Write-Log "ERRORE: cartella dati non trovata: $SagraHome"
        exit 1
    }
    if (-not (Test-Path $ResticPasswordFile)) {
        Write-Log "ERRORE: file password mancante: $ResticPasswordFile"
        exit 1
    }

    $admin = ([Security.Principal.WindowsPrincipal] `
              [Security.Principal.WindowsIdentity]::GetCurrent()
             ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    $usaVssEffettivo = $UsaVSS
    if ($UsaVSS -and -not $admin) {
        Write-Log "attenzione: privilegi non elevati, VSS disattivato per questa esecuzione"
        Write-Log "  (i file aperti in esclusiva potrebbero non essere copiati)"
        $usaVssEffettivo = $false
    }

    $env:RESTIC_PASSWORD_FILE = $ResticPasswordFile
    $env:RESTIC_COMPRESSION   = $ResticCompression

    # segnala se il database risulta in uso
    $lock = Get-ChildItem -Path $SagraHome -Include '*.ldb','*.laccdb' -File -Recurse -ErrorAction SilentlyContinue
    if ($lock) { Write-Log "nota: database risulta in uso (file di lock presente)" }

    # --------------------------------------------------------------
    # Individuazione chiavetta USB
    # --------------------------------------------------------------
    $repoUSB = $null
    if ($AbilitaUSB) {
        if ($RepoUSBFisso) {
            if (Test-Path (Split-Path $RepoUSBFisso -Parent)) { $repoUSB = $RepoUSBFisso }
        } else {
            $vol = Get-Volume -ErrorAction SilentlyContinue |
                   Where-Object { $_.FileSystemLabel -eq $EtichettaUSB -and $_.DriveLetter }
            if ($vol) {
                $repoUSB = Join-Path "$($vol.DriveLetter):\" $SottocartellaUSB
            }
        }
    }

    # --------------------------------------------------------------
    # Funzione di backup su un repository
    # --------------------------------------------------------------
    function Invoke-BackupRepo {
        param([string]$Etichetta, [string]$Repo)

        # inizializza il repository se non esiste
        & $Restic -r $Repo cat config 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            & $Restic -r $Repo init 2>&1 | Add-Content $LogFile
            if ($LASTEXITCODE -ne 0) {
                Write-Log "$Etichetta`: repository non raggiungibile, salto"
                return $false
            }
            Write-Log "$Etichetta`: repository inizializzato"
        }

        $argomenti = @('-r', $Repo, 'backup', $SagraHome,
                       '--tag', 'sagra', '--host', 'sagra',
                       '--exclude', '*.ldb', '--exclude', '*.laccdb')
        if ($usaVssEffettivo) { $argomenti += '--use-fs-snapshot' }

        & $Restic @argomenti 2>&1 | Add-Content $LogFile
        if ($LASTEXITCODE -ne 0) {
            Write-Log "$Etichetta`: ERRORE durante il backup"
            return $false
        }
        Write-Log "$Etichetta`: backup completato$(if($usaVssEffettivo){' (VSS)'})"

        & $Restic -r $Repo forget `
            --keep-last $KeepLast --keep-hourly $KeepHourly `
            --keep-daily $KeepDaily --keep-weekly $KeepWeekly `
            2>&1 | Add-Content $LogFile
        if ($LASTEXITCODE -ne 0) { Write-Log "$Etichetta`: attenzione, forget fallito" }

        # prune solo di rado
        $marker = Join-Path $StateDir "ultimo-prune-$Etichetta.txt"
        $ultimo = if (Test-Path $marker) { [datetime](Get-Content $marker -Raw).Trim() } else { [datetime]'2000-01-01' }
        if (((Get-Date) - $ultimo).TotalHours -ge $OreTraPrune) {
            & $Restic -r $Repo prune 2>&1 | Add-Content $LogFile
            if ($LASTEXITCODE -eq 0) {
                (Get-Date).ToString('o') | Set-Content $marker
                Write-Log "$Etichetta`: prune eseguito"
            } else {
                Write-Log "$Etichetta`: attenzione, prune fallito"
            }
        }
        return $true
    }

    # --------------------------------------------------------------
    # Esecuzione sulle due destinazioni
    # --------------------------------------------------------------
    $esitoUSB = 'saltato'; $esitoCloud = 'saltato'

    if ($AbilitaUSB) {
        if ($repoUSB) {
            $esitoUSB = if (Invoke-BackupRepo 'USB' $repoUSB) { 'ok' } else { 'fallito' }
        } else {
            Write-Log "USB: chiavetta '$EtichettaUSB' non trovata, salto"
            $esitoUSB = 'non inserita'
        }
    }

    if ($AbilitaCloud) {
        $Rclone = if ($RcloneExe -and (Test-Path $RcloneExe)) { $RcloneExe } else { 'rclone' }
        if (Get-Command $Rclone -ErrorAction SilentlyContinue) {
            $esitoCloud = if (Invoke-BackupRepo 'CLOUD' $RepoCloud) { 'ok' } else { 'fallito' }
        } else {
            Write-Log "CLOUD: rclone non installato, salto"
            $esitoCloud = 'rclone assente'
        }
    }

    Write-Log "riepilogo -> USB: $esitoUSB | CLOUD: $esitoCloud"

    if ($esitoUSB -eq 'ok' -or $esitoCloud -eq 'ok') { exit 0 } else { exit 1 }
}
finally {
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
