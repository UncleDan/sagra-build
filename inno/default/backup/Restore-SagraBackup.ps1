<#
.SYNOPSIS
    Elenco e ripristino dei backup della sagra.

.EXAMPLE
    .\Restore-SagraBackup.ps1 -Azione elenco
    .\Restore-SagraBackup.ps1 -Azione elenco -Destinazione cloud
    .\Restore-SagraBackup.ps1 -Azione ripristina -Snapshot latest
    .\Restore-SagraBackup.ps1 -Azione ripristina -Snapshot a1b2c3d4 -Destinazione cloud -Cartella "D:\recupero"
    .\Restore-SagraBackup.ps1 -Azione verifica
#>

[CmdletBinding()]
param(
    [ValidateSet('elenco', 'ripristina', 'verifica')]
    [string]$Azione = 'elenco',

    [ValidateSet('usb', 'cloud')]
    [string]$Destinazione = 'usb',

    [string]$Snapshot,
    [string]$Cartella = "$env:USERPROFILE\sagra-ripristino",
    [string]$Config   = "$env:ProgramData\SagraBackup\config.ps1"
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $Config)) {
    Write-Error "Configurazione non trovata: $Config"
    exit 1
}
. $Config

$env:RESTIC_PASSWORD_FILE = $ResticPasswordFile

# usa il percorso registrato dall'installer, altrimenti cerca nel PATH
$Restic = if ($ResticExe -and (Test-Path $ResticExe)) { $ResticExe } else { 'restic' }

# ------------------------------------------------------------------
# Individuazione repository
# ------------------------------------------------------------------
if ($Destinazione -eq 'cloud') {
    $Repo = $RepoCloud
} else {
    if ($RepoUSBFisso) {
        $Repo = $RepoUSBFisso
    } else {
        $vol = Get-Volume -ErrorAction SilentlyContinue |
               Where-Object { $_.FileSystemLabel -eq $EtichettaUSB -and $_.DriveLetter }
        if (-not $vol) {
            Write-Host "ERRORE: chiavetta con etichetta '$EtichettaUSB' non trovata." -ForegroundColor Red
            Write-Host "Inseriscila, oppure usa: -Destinazione cloud" -ForegroundColor Yellow
            exit 1
        }
        $Repo = Join-Path "$($vol.DriveLetter):\" $SottocartellaUSB
    }
}

Write-Host "Repository: $Repo" -ForegroundColor Cyan
Write-Host ""

switch ($Azione) {

    'elenco' {
        & $Restic -r $Repo snapshots --tag sagra
    }

    'ripristina' {
        if (-not $Snapshot) {
            Write-Host "Indica lo snapshot con -Snapshot <id|latest>" -ForegroundColor Yellow
            exit 1
        }

        Write-Host "Snapshot:     $Snapshot"
        Write-Host "Destinazione: $Cartella"
        Write-Host ""
        $conferma = Read-Host "Confermi il ripristino? [s/N]"
        if ($conferma -notmatch '^(s|si|y|yes)$') {
            Write-Host "Annullato."
            exit 0
        }

        New-Item -ItemType Directory -Path $Cartella -Force | Out-Null
        & $Restic -r $Repo restore $Snapshot --target $Cartella

        Write-Host ""
        Write-Host "Ripristino completato in: $Cartella" -ForegroundColor Green
        Write-Host ""
        Write-Host "Per rimettere in servizio i dati ripristinati:" -ForegroundColor Yellow
        Write-Host "  1. chiudi l'applicazione"
        Write-Host "  2. rinomina l'attuale $SagraHome come copia di sicurezza"
        Write-Host "  3. copia al suo posto i file ripristinati"
    }

    'verifica' {
        & $Restic -r $Repo check
    }
}
