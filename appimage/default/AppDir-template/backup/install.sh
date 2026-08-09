#!/bin/bash
# ============================================================
# install.sh - installa il backup della sagra per l'utente corrente
# Non richiede root: usa systemd --user.
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

BIN_DIR="$HOME/.local/bin"
CFG_DIR="$HOME/.config/sagra-backup"
UNIT_DIR="$HOME/.config/systemd/user"

echo "== Verifica prerequisiti =="

# ------------------------------------------------------------------
# Rilevamento del gestore pacchetti
# ------------------------------------------------------------------
rileva_gestore() {
    if   command -v apt-get >/dev/null 2>&1; then echo apt
    elif command -v dnf     >/dev/null 2>&1; then echo dnf
    elif command -v pacman  >/dev/null 2>&1; then echo pacman
    elif command -v zypper  >/dev/null 2>&1; then echo zypper
    elif command -v apk     >/dev/null 2>&1; then echo apk
    elif command -v eopkg   >/dev/null 2>&1; then echo eopkg
    else echo sconosciuto
    fi
}

# comando per i privilegi
if [ "$(id -u)" = "0" ]; then
    SUDO=""
elif command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
else
    SUDO=""
fi

installa_pacchetti() {
    local gestore="$1"; shift
    local pacchetti="$*"

    echo "  installo:$pacchetti  (gestore: $gestore)"
    case "$gestore" in
        apt)    $SUDO apt-get update -qq && $SUDO apt-get install -y $pacchetti ;;
        dnf)    $SUDO dnf install -y $pacchetti ;;
        pacman) $SUDO pacman -Sy --noconfirm $pacchetti ;;
        zypper) $SUDO zypper --non-interactive install $pacchetti ;;
        apk)    $SUDO apk add $pacchetti ;;
        eopkg)  $SUDO eopkg install -y $pacchetti ;;
        *)      return 1 ;;
    esac
}

GESTORE="$(rileva_gestore)"
DA_INSTALLARE=""

command -v restic >/dev/null 2>&1 || DA_INSTALLARE="$DA_INSTALLARE restic"
command -v rsync  >/dev/null 2>&1 || DA_INSTALLARE="$DA_INSTALLARE rsync"

# rclone serve solo per Dropbox: si chiede conferma
CHIEDI_RCLONE=0
command -v rclone >/dev/null 2>&1 || CHIEDI_RCLONE=1

if [ -n "$DA_INSTALLARE" ]; then
    echo "  mancano:$DA_INSTALLARE"

    if [ "$GESTORE" = "sconosciuto" ]; then
        echo
        echo "  ERRORE: gestore pacchetti non riconosciuto."
        echo "  Installa manualmente:$DA_INSTALLARE"
        echo "  In alternativa, restic offre un binario statico:"
        echo "    https://github.com/restic/restic/releases"
        exit 1
    fi

    if [ -z "$SUDO" ] && [ "$(id -u)" != "0" ]; then
        echo
        echo "  ERRORE: servono privilegi di amministratore per installare:$DA_INSTALLARE"
        echo "  Riesegui con sudo, oppure installali a mano:"
        case "$GESTORE" in
            apt)    echo "    sudo apt install$DA_INSTALLARE" ;;
            dnf)    echo "    sudo dnf install$DA_INSTALLARE" ;;
            pacman) echo "    sudo pacman -S$DA_INSTALLARE" ;;
            zypper) echo "    sudo zypper install$DA_INSTALLARE" ;;
            apk)    echo "    sudo apk add$DA_INSTALLARE" ;;
            eopkg)  echo "    sudo eopkg install$DA_INSTALLARE" ;;
        esac
        exit 1
    fi

    if ! installa_pacchetti "$GESTORE" $DA_INSTALLARE; then
        echo "  ERRORE: installazione fallita."
        exit 1
    fi

    # verifica finale
    MANCANO=""
    command -v restic >/dev/null 2>&1 || MANCANO="$MANCANO restic"
    command -v rsync  >/dev/null 2>&1 || MANCANO="$MANCANO rsync"
    if [ -n "$MANCANO" ]; then
        echo "  ERRORE: ancora mancanti:$MANCANO"
        exit 1
    fi
fi

echo "  restic: $(restic version 2>/dev/null | head -1 || echo presente)"
echo "  rsync:  presente"

if [ "$CHIEDI_RCLONE" = "1" ]; then
    echo
    printf "  rclone non trovato (serve solo per Dropbox). Installarlo? [S/n] "
    read -r risposta_rclone
    case "$risposta_rclone" in
        n|N|no|NO) echo "  saltato: il backup su Dropbox sara' da configurare a mano" ;;
        *)
            if [ "$GESTORE" != "sconosciuto" ]; then
                installa_pacchetti "$GESTORE" rclone || \
                    echo "  installazione di rclone non riuscita"
            fi
            ;;
    esac
fi
command -v rclone >/dev/null 2>&1 && echo "  rclone: presente"

echo "OK"

echo "== Installazione script =="
mkdir -p "$BIN_DIR" "$CFG_DIR" "$UNIT_DIR"
install -m 755 "$SCRIPT_DIR/sagra-backup.sh"  "$BIN_DIR/sagra-backup.sh"
install -m 755 "$SCRIPT_DIR/sagra-restore.sh" "$BIN_DIR/sagra-restore.sh"
echo "  -> $BIN_DIR"

echo "== Configurazione =="
if [ -f "$CFG_DIR/config" ]; then
    echo "  config gia' presente: lasciata invariata"
else
    install -m 600 "$SCRIPT_DIR/config.esempio" "$CFG_DIR/config"
    echo "  creata $CFG_DIR/config  (da adattare!)"
fi

PWFILE="$CFG_DIR/restic-password"
if [ -f "$PWFILE" ]; then
    echo "  password repository gia' presente"
else
    echo
    echo "  Serve una password per i repository restic."
    echo "  ATTENZIONE: senza questa password i backup NON sono recuperabili."
    echo "  Annotala anche altrove (es. gestore di password)."
    echo
    read -r -s -p "  Password: " P1; echo
    read -r -s -p "  Ripeti:   " P2; echo
    if [ "$P1" != "$P2" ] || [ -z "$P1" ]; then
        echo "  ERRORE: password vuota o non coincidente. Riesegui l'installazione."
        exit 1
    fi
    printf '%s' "$P1" > "$PWFILE"
    chmod 600 "$PWFILE"
    unset P1 P2
    echo "  salvata in $PWFILE (permessi 600)"
fi

echo "== Unit systemd (utente) =="
install -m 644 "$SCRIPT_DIR/systemd/sagra-backup.service" "$UNIT_DIR/"
install -m 644 "$SCRIPT_DIR/systemd/sagra-backup.timer"   "$UNIT_DIR/"
systemctl --user daemon-reload
systemctl --user enable --now sagra-backup.timer
echo "  timer attivato"

# permette al timer di funzionare anche senza sessione grafica aperta
if command -v loginctl >/dev/null 2>&1; then
    loginctl enable-linger "$USER" >/dev/null 2>&1 && \
        echo "  linger attivato (il backup gira anche a sessione chiusa)" || true
fi

cat <<FINE

============================================
Installazione completata.

PROSSIMI PASSI
  1. Adatta la configurazione:
       nano $CFG_DIR/config
     in particolare SAGRA_HOME e REPO_USB (percorso della chiavetta).

  2. Per Dropbox, configura rclone una volta sola:
       rclone config
     crea un remote di tipo 'dropbox' chiamato 'dropbox'.

  3. Prova subito un backup:
       systemctl --user start sagra-backup.service
       tail -f ~/.local/state/sagra-backup/backup.log

COMANDI UTILI
  systemctl --user list-timers sagra-backup.timer
  sagra-restore.sh elenco usb
  sagra-restore.sh elenco cloud
  sagra-restore.sh ripristina latest usb
  sagra-restore.sh verifica usb
============================================
FINE
