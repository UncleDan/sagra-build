#!/bin/bash
# ============================================================
# sagra-backup.sh
# Backup incrementale della cartella dati della sagra con restic,
# verso due repository indipendenti (chiavetta USB e Dropbox).
#
# Strategia:
#   1. mette brevemente in pausa il processo dell'applicazione
#      (SIGSTOP), cosi' il database non viene scritto durante la copia
#   2. copia rapida incrementale in staging (rsync)
#   3. riattiva subito l'applicazione (SIGCONT)
#   4. con calma salva lo staging nei due repository restic
#
# L'app resta ferma solo per il passo 2 (frazioni di secondo).
# I due repository sono indipendenti: se la chiavetta non c'e' o la
# rete e' assente, l'altro backup viene comunque completato.
# ============================================================
set -uo pipefail

CONFIG="${SAGRA_BACKUP_CONFIG:-$HOME/.config/sagra-backup/config}"

if [ ! -f "$CONFIG" ]; then
    echo "ERRORE: configurazione non trovata: $CONFIG" >&2
    echo "Copia config.esempio in quel percorso e adattalo." >&2
    exit 1
fi
# shellcheck source=/dev/null
. "$CONFIG"

export RESTIC_PASSWORD_FILE
export RESTIC_COMPRESSION="${RESTIC_COMPRESSION:-off}"

STATE_DIR="$HOME/.local/state/sagra-backup"
mkdir -p "$STATE_DIR" "$(dirname "$LOG_FILE")" "$STAGING"

# ------------------------------------------------------------------
# Log
# ------------------------------------------------------------------
log() {
    printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"
}

ruota_log() {
    [ -f "$LOG_FILE" ] || return 0
    local kb
    kb=$(du -k "$LOG_FILE" | cut -f1)
    if [ "$kb" -gt "${LOG_MAX_KB:-2048}" ]; then
        mv "$LOG_FILE" "$LOG_FILE.1"
        log "(log ruotato)"
    fi
}
ruota_log

# ------------------------------------------------------------------
# Un'esecuzione alla volta
# ------------------------------------------------------------------
LOCK="$STATE_DIR/backup.lock"
exec 9>"$LOCK"
if ! flock -n 9; then
    log "SALTATO: un backup precedente e' ancora in corso"
    exit 0
fi

ESITO_USB="saltato"
ESITO_CLOUD="saltato"

# ------------------------------------------------------------------
# Prerequisiti
# ------------------------------------------------------------------
if ! command -v restic >/dev/null 2>&1; then
    log "ERRORE: restic non installato"
    exit 1
fi
if [ ! -d "$SAGRA_HOME" ]; then
    log "ERRORE: cartella dati non trovata: $SAGRA_HOME"
    exit 1
fi
if [ ! -f "$RESTIC_PASSWORD_FILE" ]; then
    log "ERRORE: file password mancante: $RESTIC_PASSWORD_FILE"
    exit 1
fi

# ------------------------------------------------------------------
# 1-3. Preparazione di una copia coerente
#
# Tre metodi, in ordine di preferenza (config: METODO):
#   snapshot -> snapshot del filesystem (Btrfs/ZFS/LVM): l'equivalente
#               piu' fedele di VSS. Richiede privilegi di root.
#   pausa    -> SIGSTOP all'applicazione + rsync in staging + SIGCONT.
#               Non richiede privilegi. L'app resta ferma pochi ms.
#   auto     -> prova snapshot, altrimenti ripiega su pausa.
# ------------------------------------------------------------------
METODO="${METODO:-auto}"
SNAPSHOT_DIR=""
METODO_USATO=""

# comando per eseguire operazioni privilegiate senza chiedere password
if [ "$(id -u)" = "0" ]; then
    SUDO=""
    HA_ROOT=1
elif sudo -n true 2>/dev/null; then
    SUDO="sudo -n"
    HA_ROOT=1
else
    SUDO=""
    HA_ROOT=0
fi

# segnala se il database risulta aperto (file di lock Access presente)
if compgen -G "$SAGRA_HOME/*.ldb" >/dev/null 2>&1 || \
   compgen -G "$SAGRA_HOME/*.laccdb" >/dev/null 2>&1; then
    log "nota: database risulta in uso (file di lock presente)"
fi

TIPO_FS="$(stat -f -c %T "$SAGRA_HOME" 2>/dev/null || echo sconosciuto)"

# ------------------------------------------------------------------
# Metodo A: snapshot del filesystem
# ------------------------------------------------------------------
prova_snapshot() {
    [ "$HA_ROOT" = "1" ] || { log "snapshot: servono privilegi di root, non disponibili"; return 1; }

    local base="$STATE_DIR/snap"
    rm -rf "$base" 2>/dev/null || true

    case "$TIPO_FS" in
        btrfs)
            command -v btrfs >/dev/null 2>&1 || { log "snapshot: comando btrfs assente"; return 1; }
            # la cartella dev'essere un subvolume
            if ! $SUDO btrfs subvolume show "$SAGRA_HOME" >/dev/null 2>&1; then
                log "snapshot: $SAGRA_HOME non e' un subvolume Btrfs"
                return 1
            fi
            if $SUDO btrfs subvolume snapshot -r "$SAGRA_HOME" "$base" >/dev/null 2>&1; then
                SNAPSHOT_DIR="$base"
                METODO_USATO="snapshot Btrfs"
                return 0
            fi
            log "snapshot: creazione subvolume fallita"
            return 1
            ;;
        zfs)
            command -v zfs >/dev/null 2>&1 || { log "snapshot: comando zfs assente"; return 1; }
            local ds
            ds="$(df --output=source "$SAGRA_HOME" 2>/dev/null | tail -1)"
            [ -n "$ds" ] || return 1
            local nome="sagra-backup-$(date +%s)"
            if $SUDO zfs snapshot "${ds}@${nome}" >/dev/null 2>&1; then
                # ZFS espone gli snapshot nella cartella nascosta .zfs
                local mnt rel
                mnt="$(df --output=target "$SAGRA_HOME" | tail -1)"
                rel="${SAGRA_HOME#$mnt}"
                SNAPSHOT_DIR="$mnt/.zfs/snapshot/$nome$rel"
                ZFS_SNAP="${ds}@${nome}"
                METODO_USATO="snapshot ZFS"
                [ -d "$SNAPSHOT_DIR" ] && return 0
                $SUDO zfs destroy "$ZFS_SNAP" >/dev/null 2>&1 || true
                log "snapshot: cartella .zfs/snapshot non accessibile"
                return 1
            fi
            return 1
            ;;
        *)
            # LVM: funziona con qualsiasi filesystem sopra un volume logico
            command -v lvs >/dev/null 2>&1 || { log "snapshot: filesystem $TIPO_FS senza snapshot nativi e LVM assente"; return 1; }
            local dev
            dev="$(df --output=source "$SAGRA_HOME" 2>/dev/null | tail -1)"
            if ! $SUDO lvs "$dev" >/dev/null 2>&1; then
                log "snapshot: $dev non e' un volume logico LVM"
                return 1
            fi
            local lvname="sagra_snap_$(date +%s)"
            if $SUDO lvcreate -s -L 1G -n "$lvname" "$dev" >/dev/null 2>&1; then
                mkdir -p "$base"
                local vg
                vg="$($SUDO lvs --noheadings -o vg_name "$dev" | tr -d ' ')"
                LVM_SNAP="/dev/$vg/$lvname"
                if $SUDO mount -o ro "$LVM_SNAP" "$base" >/dev/null 2>&1; then
                    SNAPSHOT_DIR="$base"
                    METODO_USATO="snapshot LVM"
                    return 0
                fi
                $SUDO lvremove -f "$LVM_SNAP" >/dev/null 2>&1 || true
            fi
            return 1
            ;;
    esac
}

pulisci_snapshot() {
    case "$METODO_USATO" in
        "snapshot Btrfs") $SUDO btrfs subvolume delete "$SNAPSHOT_DIR" >/dev/null 2>&1 || true ;;
        "snapshot ZFS")   $SUDO zfs destroy "${ZFS_SNAP:-}" >/dev/null 2>&1 || true ;;
        "snapshot LVM")   $SUDO umount "$SNAPSHOT_DIR" >/dev/null 2>&1 || true
                          $SUDO lvremove -f "${LVM_SNAP:-}" >/dev/null 2>&1 || true ;;
    esac
}

# ------------------------------------------------------------------
# Metodo B: pausa dell'applicazione + staging
# ------------------------------------------------------------------
usa_pausa() {
    PIDS=""
    if [ -n "${PROCESSO_APP:-}" ]; then
        PIDS="$(pgrep -f "$PROCESSO_APP" 2>/dev/null || true)"
    fi

    riattiva() {
        if [ -n "$PIDS" ]; then
            for p in $PIDS; do kill -CONT "$p" 2>/dev/null || true; done
        fi
    }
    # se lo script viene interrotto, l'app non deve restare congelata
    trap riattiva EXIT INT TERM

    local t0 t1
    t0=$(date +%s%N)
    if [ -n "$PIDS" ]; then
        for p in $PIDS; do kill -STOP "$p" 2>/dev/null || true; done
    fi

    rsync -a --delete "$SAGRA_HOME/" "$STAGING/"
    local rc=$?

    if [ -n "$PIDS" ]; then
        for p in $PIDS; do kill -CONT "$p" 2>/dev/null || true; done
    fi
    trap - EXIT INT TERM
    t1=$(date +%s%N)

    if [ $rc -ne 0 ]; then
        log "ERRORE: copia in staging fallita (rsync rc=$rc)"
        return 1
    fi
    METODO_USATO="pausa applicazione"
    log "staging aggiornato (app in pausa $(( (t1 - t0) / 1000000 )) ms)"
    return 0
}

# ------------------------------------------------------------------
# Scelta del metodo
# ------------------------------------------------------------------
case "$METODO" in
    snapshot)
        if ! prova_snapshot; then
            log "ERRORE: metodo 'snapshot' richiesto ma non disponibile"
            exit 1
        fi
        ;;
    pausa)
        usa_pausa || exit 1
        ;;
    auto|*)
        if prova_snapshot; then
            log "uso $METODO_USATO (filesystem: $TIPO_FS)"
        else
            log "ripiego sul metodo 'pausa applicazione'"
            usa_pausa || exit 1
        fi
        ;;
esac

# sorgente effettiva per restic
if [ -n "$SNAPSHOT_DIR" ]; then
    SORGENTE_BACKUP="$SNAPSHOT_DIR"
    trap pulisci_snapshot EXIT INT TERM
else
    SORGENTE_BACKUP="$STAGING"
fi

# ------------------------------------------------------------------
# 4. Backup nei repository
# ------------------------------------------------------------------
esegui_backup() {
    local etichetta="$1" repo="$2"

    # inizializza il repository se non esiste ancora
    if ! restic -r "$repo" cat config >/dev/null 2>&1; then
        if restic -r "$repo" init >/dev/null 2>&1; then
            log "$etichetta: repository inizializzato"
        else
            log "$etichetta: repository non raggiungibile, salto"
            return 1
        fi
    fi

    if restic -r "$repo" backup "$SORGENTE_BACKUP" \
            --tag sagra --host sagra \
            --exclude '*.ldb' --exclude '*.laccdb' \
            >>"$LOG_FILE" 2>&1; then
        log "$etichetta: backup completato"
    else
        log "$etichetta: ERRORE durante il backup"
        return 1
    fi

    restic -r "$repo" forget \
        --keep-last "$KEEP_LAST" \
        --keep-hourly "$KEEP_HOURLY" \
        --keep-daily "$KEEP_DAILY" \
        --keep-weekly "$KEEP_WEEKLY" \
        >>"$LOG_FILE" 2>&1 || log "$etichetta: attenzione, forget fallito"

    # prune solo di rado: e' l'operazione piu' pesante
    local marker="$STATE_DIR/ultimo-prune-$etichetta"
    local adesso ultimo
    adesso=$(date +%s)
    ultimo=$(cat "$marker" 2>/dev/null || echo 0)
    if [ $(( (adesso - ultimo) / 3600 )) -ge "${ORE_TRA_PRUNE:-24}" ]; then
        if restic -r "$repo" prune >>"$LOG_FILE" 2>&1; then
            echo "$adesso" > "$marker"
            log "$etichetta: prune eseguito"
        else
            log "$etichetta: attenzione, prune fallito"
        fi
    fi
    return 0
}

# --- chiavetta USB ---
if [ "${ABILITA_USB:-0}" = "1" ]; then
    MOUNT_USB="$(dirname "$REPO_USB")"
    if mountpoint -q "$MOUNT_USB" 2>/dev/null || [ -d "$MOUNT_USB" ]; then
        if esegui_backup "USB" "$REPO_USB"; then ESITO_USB="ok"; else ESITO_USB="fallito"; fi
    else
        log "USB: chiavetta non montata ($MOUNT_USB), salto"
        ESITO_USB="non montata"
    fi
fi

# --- Dropbox via rclone ---
if [ "${ABILITA_CLOUD:-0}" = "1" ]; then
    if command -v rclone >/dev/null 2>&1; then
        if esegui_backup "CLOUD" "$REPO_CLOUD"; then ESITO_CLOUD="ok"; else ESITO_CLOUD="fallito"; fi
    else
        log "CLOUD: rclone non installato, salto"
        ESITO_CLOUD="rclone assente"
    fi
fi

log "riepilogo -> USB: $ESITO_USB | CLOUD: $ESITO_CLOUD"

# esito non-zero solo se entrambe le destinazioni sono fallite
if [ "$ESITO_USB" = "ok" ] || [ "$ESITO_CLOUD" = "ok" ]; then
    exit 0
fi
exit 1
