#!/bin/bash
# ============================================================
# sagra-restore.sh
# Elenco e ripristino dei backup della sagra.
#
#   ./sagra-restore.sh elenco            elenca gli snapshot (USB)
#   ./sagra-restore.sh elenco cloud      elenca gli snapshot (Dropbox)
#   ./sagra-restore.sh ripristina <id> [usb|cloud] [destinazione]
#   ./sagra-restore.sh verifica [usb|cloud]
# ============================================================
set -uo pipefail

CONFIG="${SAGRA_BACKUP_CONFIG:-$HOME/.config/sagra-backup/config}"
if [ ! -f "$CONFIG" ]; then
    echo "ERRORE: configurazione non trovata: $CONFIG" >&2
    exit 1
fi
# shellcheck source=/dev/null
. "$CONFIG"
export RESTIC_PASSWORD_FILE

scegli_repo() {
    case "${1:-usb}" in
        usb|USB)     echo "$REPO_USB" ;;
        cloud|CLOUD) echo "$REPO_CLOUD" ;;
        *) echo "ERRORE: destinazione non valida: $1 (usa 'usb' o 'cloud')" >&2; exit 1 ;;
    esac
}

AZIONE="${1:-elenco}"

case "$AZIONE" in
    elenco)
        REPO="$(scegli_repo "${2:-usb}")"
        echo "Repository: $REPO"
        echo
        restic -r "$REPO" snapshots --tag sagra
        ;;

    ripristina)
        ID="${2:-}"
        if [ -z "$ID" ]; then
            echo "Uso: $(basename "$0") ripristina <id-snapshot|latest> [usb|cloud] [destinazione]"
            exit 1
        fi
        REPO="$(scegli_repo "${3:-usb}")"
        DEST="${4:-$HOME/sagra-ripristino}"

        echo "Repository:  $REPO"
        echo "Snapshot:    $ID"
        echo "Destinazione: $DEST"
        echo
        read -r -p "Confermi il ripristino? [s/N] " risposta
        case "$risposta" in
            s|S|si|SI|y|Y) ;;
            *) echo "Annullato."; exit 0 ;;
        esac

        mkdir -p "$DEST"
        restic -r "$REPO" restore "$ID" --target "$DEST"

        echo
        echo "Ripristino completato in: $DEST"
        echo "I file si trovano nella sottocartella corrispondente al percorso originale."
        echo
        echo "Per rimettere in servizio i dati ripristinati:"
        echo "  1. chiudi l'applicazione"
        echo "  2. sposta l'attuale $SAGRA_HOME come copia di sicurezza"
        echo "  3. copia i file ripristinati al suo posto"
        ;;

    verifica)
        REPO="$(scegli_repo "${2:-usb}")"
        echo "Verifica integrita' di: $REPO"
        restic -r "$REPO" check
        ;;

    *)
        echo "Azione non riconosciuta: $AZIONE"
        echo
        sed -n '3,12p' "$0" | sed 's/^# \{0,1\}//'
        exit 1
        ;;
esac
