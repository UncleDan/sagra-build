# ============================================================
# Configurazione backup sagra (Windows)
# Copiare in %ProgramData%\SagraBackup\config.ps1 e adattare.
# ============================================================

# --- Cartella dati da salvare ---
$SagraHome = 'C:\SAGRA_SANT-AGOSTINO'
# per la versione standard:
# $SagraHome = 'C:\SAGRA'

# --- Repository 1: chiavetta USB ---
# Indicare l'etichetta del volume: la lettera di unita' puo' cambiare,
# l'etichetta no. Lo script cerca la chiavetta per etichetta.
$EtichettaUSB     = 'BACKUP_SAGRA'
$SottocartellaUSB = 'restic-sagra-santagostino'

# In alternativa, percorso fisso (se valorizzato ha la precedenza):
$RepoUSBFisso = ''

# --- Repository 2: Dropbox via rclone ---
# 'dropbox' e' il nome del remote configurato con: rclone config
$RepoCloud = 'rclone:dropbox:Backup/sagra/restic-sagra-santagostino'

# Mettere a $false per disattivare una destinazione.
$AbilitaUSB   = $true
$AbilitaCloud = $true

# --- Percorsi degli eseguibili ---
# Vuoto = cercati nel PATH. L'installer li compila automaticamente,
# utile perche' winget puo' installare restic in modalita' "portable"
# senza creare l'alias nel PATH.
$ResticExe = ''
$RcloneExe = ''

# --- Password del repository restic ---
$ResticPasswordFile = "$env:ProgramData\SagraBackup\restic-password.txt"

# --- Compressione restic: off | auto | max ---
# 'off' e' il piu' veloce; la deduplica funziona comunque.
$ResticCompression = 'off'

# --- VSS ---
# $true usa Volume Shadow Copy: copia i file anche se aperti in
# esclusiva dall'applicazione. Richiede privilegi amministrativi.
$UsaVSS = $true

# --- Retention ---
$KeepLast   = 72     # ultimi 72 snapshot (~12 ore a 10 min)
$KeepHourly = 48
$KeepDaily  = 14
$KeepWeekly = 8

# Il 'prune' recupera spazio ma e' pesante: non piu' di una volta
# ogni tot ore.
$OreTraPrune = 24

# --- Log ---
$LogFile   = "$env:ProgramData\SagraBackup\backup.log"
$LogMaxKB  = 2048
