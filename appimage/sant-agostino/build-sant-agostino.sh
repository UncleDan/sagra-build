#!/bin/bash
# ============================================================
# build-sant-agostino.sh
# Costruisce l'AppImage della variante SANT'AGOSTINO direttamente da Linux
# (anche da sessione live).
#
# Sorgente dell'applicazione, in ordine di priorita':
#   1. percorso passato come argomento:   ./build-sant-agostino.sh /media/d/C-SISTEMA/SAGRA_SANT-AGOSTINO
#   2. contenuto gia' presente in appdata/
#   3. ricerca automatica sui dischi montati
#
# Output: dist/GestioneStandGastronomico-SantAgostino-x86_64.AppImage
# ============================================================
set -e

# readlink -f risolve anche eventuali symlink, cosi' i percorsi
# restano relativi alla vera posizione dello script
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

VARIANTE="sant-agostino"
APP_EXE="Sagra3.4.0.exe"
WIN_DIRNAME="SAGRA_SANT-AGOSTINO"
APP_NAME="GestioneStandGastronomico-SantAgostino"

APPDATA_DIR="$SCRIPT_DIR/appdata"
BUILD_DIR="$SCRIPT_DIR/AppDir"
OUTPUT_DIR="$SCRIPT_DIR/dist"
COMMON_SYS="$SCRIPT_DIR/../common/sys"
APPIMAGETOOL="$SCRIPT_DIR/appimagetool.AppImage"

SORGENTE="${1:-}"

echo "============================================"
echo " Build AppImage - variante: $VARIANTE"
echo "============================================"

# ------------------------------------------------------------------
# 1. Prerequisiti
# ------------------------------------------------------------------
if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    if [ ! -f "$APPIMAGETOOL" ]; then
        echo "ERRORE: servono 'curl' o 'wget' per scaricare appimagetool."
        echo "In alternativa scaricalo a mano e salvalo come:"
        echo "  $APPIMAGETOOL"
        exit 1
    fi
fi

# ------------------------------------------------------------------
# 1b. Runtime VB6: popola common/sys se mancante
# ------------------------------------------------------------------
LISTA_RUNTIME="$SCRIPT_DIR/../common/runtime-richiesti.txt"

mkdir -p "$COMMON_SYS"
MANCANTI=0
if [ -f "$LISTA_RUNTIME" ]; then
    while IFS= read -r rf; do
        [ -n "$rf" ] || continue
        [ -e "$COMMON_SYS/$rf" ] || MANCANTI=1
    done < "$LISTA_RUNTIME"
else
    [ -e "$COMMON_SYS/msvbvm60.dll" ] || MANCANTI=1
fi

if [ "$MANCANTI" -eq 1 ]; then
    echo "== Runtime VB6 mancanti in common/sys: cerco una sorgente =="

    # cerca SysWOW64 (o System32) su una partizione Windows montata
    SRC_SYS=""
    for root in /media /mnt /run/media; do
        [ -d "$root" ] || continue
        while IFS= read -r d; do
            [ -n "$d" ] || continue
            if [ -f "$d/msvbvm60.dll" ] || [ -f "$d/MSVBVM60.DLL" ]; then
                SRC_SYS="$d"; break
            fi
        done <<< "$(find "$root" -maxdepth 5 -type d \( -iname 'SysWOW64' -o -iname 'System32' \) 2>/dev/null)"
        [ -n "$SRC_SYS" ] && break
    done

    if [ -z "$SRC_SYS" ]; then
        echo "ERRORE: non trovo i runtime VB6."
        echo
        echo "Opzioni:"
        echo "  - monta la partizione Windows (i file stanno in Windows\\SysWOW64)"
        echo "  - oppure copia a mano i file elencati in"
        echo "    common/runtime-richiesti.txt dentro common/sys/"
        exit 1
    fi

    echo "Sorgente trovata: $SRC_SYS"
    while IFS= read -r rf; do
        [ -n "$rf" ] || continue
        [ -e "$COMMON_SYS/$rf" ] && continue
        # ricerca senza distinzione maiuscole/minuscole
        trovato="$(find "$SRC_SYS" -maxdepth 1 -iname "$rf" 2>/dev/null | head -1)"
        if [ -n "$trovato" ]; then
            cp "$trovato" "$COMMON_SYS/$rf"
            echo "  [copiato]  $rf"
        else
            echo "  [MANCANTE] $rf"
        fi
    done < "$LISTA_RUNTIME"
    chmod -R u+rwX "$COMMON_SYS" 2>/dev/null || true
    echo
fi

# ------------------------------------------------------------------
# 2. Individuazione sorgente applicazione
# ------------------------------------------------------------------
if [ -z "$SORGENTE" ] && [ -f "$APPDATA_DIR/$APP_EXE" ]; then
    echo "Uso i file gia' presenti in appdata/"
elif [ -z "$SORGENTE" ]; then
    echo "== Ricerca installazione sui dischi montati =="
    TROVATI=""
    for root in /media /mnt /run/media; do
        [ -d "$root" ] || continue
        while IFS= read -r d; do
            [ -n "$d" ] || continue
            [ -f "$d/$APP_EXE" ] && TROVATI="$TROVATI$d"$'\n'
        done <<< "$(find "$root" -maxdepth 6 -type d -iname "$WIN_DIRNAME" 2>/dev/null)"
    done
    TROVATI="$(printf '%s' "$TROVATI" | sed '/^$/d')"
    NUM=$(printf '%s\n' "$TROVATI" | sed '/^$/d' | wc -l)

    if [ "$NUM" -eq 1 ]; then
        SORGENTE="$TROVATI"
        echo "Trovata: $SORGENTE"
    elif [ "$NUM" -gt 1 ]; then
        echo "Trovate piu' installazioni:"
        printf '%s\n' "$TROVATI" | sed 's/^/  - /'
        echo
        echo "Rilancia indicando quella giusta:  $(basename "$0") \"<percorso>\""
        exit 1
    else
        echo "ERRORE: nessuna installazione trovata e appdata/ e' vuota."
        echo
        echo "Indica la cartella con $APP_EXE, ad esempio:"
        echo "  $(basename "$0") /media/d/C-SISTEMA/$WIN_DIRNAME"
        echo
        echo "Se la partizione Windows non e' montata, montala prima."
        exit 1
    fi
fi

# ------------------------------------------------------------------
# 3. Copia sorgente in appdata/
# ------------------------------------------------------------------
if [ -n "$SORGENTE" ]; then
    if [ ! -d "$SORGENTE" ]; then
        echo "ERRORE: cartella non trovata: $SORGENTE"; exit 1
    fi
    if [ ! -f "$SORGENTE/$APP_EXE" ]; then
        echo "ERRORE: $APP_EXE non presente in $SORGENTE"; exit 1
    fi

    echo "== Copia applicazione da $SORGENTE =="
    mkdir -p "$APPDATA_DIR"
    find "$APPDATA_DIR" -mindepth 1 -maxdepth 1 \
         ! -name '.gitkeep' ! -name 'LEGGIMI.txt' -exec rm -rf {} + 2>/dev/null || true
    cp -r "$SORGENTE/." "$APPDATA_DIR/"
    # i file provenienti da NTFS possono arrivare in sola lettura
    chmod -R u+rwX "$APPDATA_DIR" 2>/dev/null || true
    echo "Copiati $(find "$APPDATA_DIR" -type f | wc -l) file."
fi

# ------------------------------------------------------------------
# 4. Assemblaggio AppDir
# ------------------------------------------------------------------
echo "== Assemblaggio AppDir =="
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/usr/share/sagra/sys"
mkdir -p "$BUILD_DIR/usr/share/sagra/app"
mkdir -p "$OUTPUT_DIR"

cp "$SCRIPT_DIR/AppDir-template/AppRun" "$BUILD_DIR/AppRun"
chmod +x "$BUILD_DIR/AppRun"
cp "$SCRIPT_DIR/AppDir-template/sagra.desktop" "$BUILD_DIR/sagra.desktop"
cp "$SCRIPT_DIR/AppDir-template/sagra.png" "$BUILD_DIR/sagra.png"
cp "$SCRIPT_DIR/AppDir-template/sagra.png" "$BUILD_DIR/.DirIcon"

# la forma "/." copia anche i file nascosti (che il glob "*" salterebbe)
cp -r "$COMMON_SYS/." "$BUILD_DIR/usr/share/sagra/sys/"

# script di backup (restic), se presenti nel template
if [ -d "$SCRIPT_DIR/AppDir-template/backup" ]; then
    mkdir -p "$BUILD_DIR/usr/share/sagra/backup"
    cp -r "$SCRIPT_DIR/AppDir-template/backup/." "$BUILD_DIR/usr/share/sagra/backup/"
    chmod +x "$BUILD_DIR/usr/share/sagra/backup/"*.sh 2>/dev/null || true
fi
cp -r "$APPDATA_DIR/." "$BUILD_DIR/usr/share/sagra/app/"
rm -f "$BUILD_DIR/usr/share/sagra/app/LEGGIMI.txt" \
      "$BUILD_DIR/usr/share/sagra/app/.gitkeep"

# ------------------------------------------------------------------
# 5. appimagetool
# ------------------------------------------------------------------
if [ ! -f "$APPIMAGETOOL" ]; then
    echo "== Download appimagetool (solo la prima volta) =="
    ARCH_DL="$(uname -m)"
    URL="https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-${ARCH_DL}.AppImage"
    if command -v curl >/dev/null 2>&1; then
        curl -L -o "$APPIMAGETOOL" "$URL"
    else
        wget -O "$APPIMAGETOOL" "$URL"
    fi
    chmod +x "$APPIMAGETOOL"
fi

# ------------------------------------------------------------------
# 6. Generazione AppImage
# ------------------------------------------------------------------
echo "== Generazione AppImage =="
# senza /dev/fuse (container, alcune live) appimagetool si auto-estrae
if [ ! -e /dev/fuse ]; then
    export APPIMAGE_EXTRACT_AND_RUN=1
fi

ARCH="$(uname -m)" "$APPIMAGETOOL" "$BUILD_DIR" "$OUTPUT_DIR/${APP_NAME}-x86_64.AppImage"

echo
echo "== Completato =="
ls -lh "$OUTPUT_DIR/${APP_NAME}-x86_64.AppImage"
echo
echo "Per usarla:"
echo "  chmod +x \"$OUTPUT_DIR/${APP_NAME}-x86_64.AppImage\""
echo "  \"$OUTPUT_DIR/${APP_NAME}-x86_64.AppImage\""
