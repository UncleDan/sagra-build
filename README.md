# Gestione Stand Gastronomico — pacchetti di distribuzione

Progetto per distribuire l'applicazione VB6 `Sagra3.4.0.exe` su Windows
(installer Inno Setup) e su Linux (AppImage con Wine).

Due varianti, sempre separate:

| Variante        | Sorgente Windows          |
|-----------------|---------------------------|
| `default`       | `C:\SAGRA`                |
| `sant-agostino` | `C:\SAGRA_SANT-AGOSTINO`  |

## I 4 script

| # | Script | Dove si lancia | Produce |
|---|--------|----------------|---------|
| 1 | `inno/default/setup.iss` + `build.bat` | Windows (Inno Setup) | `Sagra3.4.0_setup.exe` |
| 2 | `appimage/default/build-default.sh` | Linux / live | `GestioneStandGastronomico-x86_64.AppImage` |
| 3 | `inno/sant-agostino/setup.iss` + `build.bat` | Windows (Inno Setup) | `SAGRA_SANT-AGOSTINO_setup_<timestamp>.exe` |
| 4 | `appimage/sant-agostino/build-sant-agostino.sh` | Linux / live | `GestioneStandGastronomico-SantAgostino-x86_64.AppImage` |

Ogni script è dedicato alla propria variante: nessun parametro
obbligatorio, nessuna scelta da fare al lancio.

Gli installer Windows si costruiscono su Windows, le AppImage su Linux
(anche da sessione live).

---

## 1 e 3 — Installer Windows (Inno Setup)

Doppio click su `build.bat` nella cartella della variante. Lo script:
- popola `sys\` automaticamente se vuota, copiando i runtime VB6 da
  `%SystemRoot%\SysWOW64` (o `System32` su sistemi a 32 bit)
- individua `ISCC.exe` e compila `setup.iss`
- scrive il risultato in `dist\`

In alternativa, da riga di comando:

```cmd
"C:\Program Files (x86)\Inno Setup 6\ISCC.exe" /O"dist" "setup.iss"
```

**Cartella di installazione**: `C:\SAGRA` e `C:\SAGRA_SANT-AGOSTINO`,
non `Program Files`. È voluto: l'applicazione VB6 scrive i propri dati
accanto a sé stessa e usa percorsi assoluti, quindi Program Files
(protetta da UAC e soggetta a virtualizzazione) creerebbe problemi.

Se la cartella esiste già, il setup avvisa prima di procedere, con due
livelli:
- contiene file generici → avviso semplice
- contiene database o file `.ini` → avviso esplicito che segnala il
  rischio di sovrascrittura e consiglia una copia di sicurezza

Cosa fa l'installer prodotto:
- installa i runtime VB6 (cartella `sys\`) in `SysWOW64`, registrando
  **solo** i componenti che lo supportano (le OCX, `MSSTDFMT.DLL`,
  `msvbvm60.dll`)
- copia l'applicazione in `Program Files (x86)`
- crea icona nel menu Start e sul **desktop di tutti gli utenti**
- in disinstallazione **chiede conferma** prima di eliminare la
  cartella con i dati

L'installer resta a **32 bit** (nessun `ArchitecturesInstallIn64BitMode`):
è necessario perché l'app VB6 a 32 bit cerca `msvbvm60.dll` in
`SysWOW64`.

Il setup Sant'Agostino include un **timestamp di generazione** nel nome
del file (`yyyymmdd_hhnnss`).

---

## 2 e 4 — AppImage da Linux (anche sessione live)

```bash
chmod +x build-default.sh
./build-default.sh                              # cerca da solo sui dischi montati
./build-default.sh /media/d/C-SISTEMA/SAGRA     # sorgente esplicita
```

Lo script:
1. usa il percorso passato come argomento, oppure quanto già presente
   in `appdata/`, oppure cerca automaticamente su `/media`, `/mnt`,
   `/run/media`
2. normalizza i permessi dei file provenienti da NTFS
3. scarica `appimagetool` al primo utilizzo (serve `curl` o `wget`)
4. produce l'AppImage in `dist/`

Se la partizione Windows non è montata, montala prima (di solito basta
cliccarla nella barra laterale del file manager). Per costruire non
serve Wine: quello serve solo per *eseguire* l'AppImage.

---


### Registrazione: cosa si registra e cosa no

Non tutti i file in `sys\` vanno passati a `regsvr32`:

| File | Trattamento |
|---|---|
| `*.ocx`, `MSSTDFMT.DLL`, `msvbvm60.dll` | copiati e **registrati** |
| `asycfilt.dll`, `comcat.dll`, `olepro32.dll`, `oleaut32.dll`, `stdole2.tlb` | copiati **solo se mancanti**, mai registrati |

`asycfilt.dll` non espone `DllRegisterServer` e `stdole2.tlb` è una
type library (servirebbe `regtlib`): passarli a `regsvr32` fa fallire
l'installazione con *"RegSvr32 è fallito con codice di uscita 0x4"*.

Su Windows XP SP2 e successivi quei cinque file fanno parte del
sistema operativo e sono protetti da Windows File Protection, quindi
sovrascriverli è inutile e potenzialmente dannoso — per questo hanno
il flag `onlyifdoesntexist`. È lo stesso motivo per cui l'AppImage le
salta: Wine fornisce le proprie versioni.

## Runtime VB6 (`appimage/common/sys`, `inno/*/sys`)

Due cartelle distinte:

| Cartella | Contenuto |
|---|---|
| `common/sys` | i componenti estratti dall'installer originale |
| `common/sys-extra` | controlli VB6 aggiuntivi (~2,9 MB), inclusi solo nell'AppImage |

`sys-extra` esiste per un motivo preciso: un form VB6 carica i propri
controlli **per CLSID**, e quel riferimento è compilato in forma
binaria dentro l'eseguibile — non compare come testo, quindi
`--analizza` non può vederlo. Se manca anche un solo controllo usato da
un form, VB6 solleva `Runtime error 429`. Includerli tutti costa pochi
MB ed elimina il problema senza doverli indovinare.

Su Windows non servono: sono già presenti sulla macchina.

Le cartelle sono già popolate con i componenti estratti dall'installer
originale. Se le svuoti o parti da zero, **gli script le ripopolano da
soli**:

- gli script Windows (`build.bat`, `.ps1`) copiano da
  `%SystemRoot%\SysWOW64`
- gli script Linux (`.sh`) cercano una cartella `SysWOW64`/`System32`
  su una partizione Windows montata

L'elenco dei file richiesti è in `appimage/common/runtime-richiesti.txt`
(13 file: `msvbvm60.dll`, le OCX dei controlli, le librerie OLE di
supporto). Se qualcosa manca, lo script lo segnala per nome.

Nota: i runtime VB6 non sono più distribuiti da Microsoft con un
download stabile, quindi la copia dalla propria macchina Windows —
dove sono già presenti perché l'applicazione ci gira — è il metodo
più affidabile.

---

## Voci di menu su Linux

L'AppImage crea a ogni avvio le proprie voci di menu, raggruppate in
una cartella dedicata (`Gestione Stand Gastronomico`, oppure
`... - Sant'Agostino`):

- **Gestione Stand Gastronomico** — avvia l'applicazione
- **Report Sagra** — apre il report nel browser (solo se il file è
  presente)

Il raggruppamento usa un file `.directory` più un file `.menu` in
`~/.config/menus/applications-merged`. Funziona su XFCE, KDE, MATE e
Cinnamon; GNOME ignora le cartelle di menu e mostra le voci singole.

Le voci vengono riscritte a ogni avvio, così restano valide anche se
sposti l'AppImage.

## Diagnostica del runtime Wine

```bash
./GestioneStandGastronomico-x86_64.AppImage --diagnostica
./GestioneStandGastronomico-x86_64.AppImage --ripara-runtime
```

`--diagnostica` verifica quali librerie sono installate, prova a
registrare i controlli riportando gli esiti uno per uno, e controlla
la presenza dei componenti di accesso ai dati (Jet/DAO/ADO) — la causa
più comune di `Runtime error 429`.

`--ripara-runtime` forza la reinstallazione e registrazione delle
librerie.

Se i controlli si registrano tutti ma l'errore 429 persiste, il
componente mancante non e' tra quelli distribuiti. Due strumenti per
individuarlo:

```bash
# analisi statica: cerca nell'eseguibile i riferimenti a librerie
# e segnala quali non sono presenti nel prefix Wine
./GestioneStandGastronomico-x86_64.AppImage --analizza

# tracciamento: avvia l'app registrando gli errori OLE
./GestioneStandGastronomico-x86_64.AppImage --traccia
```

La causa piu' frequente in un gestionale VB6 con database Access sono
i componenti di accesso ai dati (Jet/DAO/ADO), che Wine non include:

```bash
./GestioneStandGastronomico-x86_64.AppImage --installa-dati
```

che equivale a `winetricks -q vb6run jet40 mdac28` sul prefix giusto.

In alternativa, i file segnalati come assenti da `--analizza` si
possono copiare dal PC Windows (di norma da `C:\Windows\SysWOW64`)
dentro `drive_c/windows/system32` del prefix, poi rilanciare
`--ripara-runtime`. Per includerli stabilmente in tutte le build
future, mettili in `appimage/common/sys/` e aggiungi il nome a
`appimage/common/runtime-richiesti.txt`.

### Falso positivo noto: `vba6.dll`

`--analizza` segnala `vba6.dll` come assente su qualsiasi applicazione
VB6. È normale: l'intestazione di ogni eseguibile VB6 contiene quella
stringa come nome del runtime di progetto, ma il file realmente
caricato è `msvbvm60.dll`. Serve davvero solo se l'applicazione ospita
macro VBA.

Se dovesse servire, `vba6.dll` **non si trova in SysWOW64**: il
percorso tipico è

```
C:\Program Files (x86)\Common Files\Microsoft Shared\VBA\VBA6\VBA6.DLL
```

ed è presente solo se sulla macchina è installato Office o l'IDE
Visual Basic 6. Vedi `appimage/common/runtime-opzionali.txt`.

## Report HTML (`report-sagra.html`)

Se il file `report-sagra.html` è presente nella cartella dell'app,
viene creato automaticamente un collegamento dedicato per aprirlo nel
browser:

- **Windows**: voce "Report Sagra" nel menu Start e sul desktop di
  tutti gli utenti. I collegamenti vengono creati solo se il file è
  stato effettivamente installato (`Check: ReportPresente`).
- **Linux**: al primo avvio l'AppImage crea la voce di menu "Report
  Sagra" in `~/.local/share/applications`, che richiama l'AppImage con
  l'opzione `--report`. Puoi usarla anche da terminale:

  ```bash
  ./GestioneStandGastronomico-x86_64.AppImage --report
  ```

Se il file non c'è, non viene creato nessun collegamento e tutto
funziona come prima.

---

## Copia dei file

Tutti i file della cartella sorgente vengono copiati, **compresi
quelli nascosti** (nomi che iniziano con un punto) e le sottocartelle
a qualsiasi livello. Vale sia per la fase di build (sorgente →
AppImage/installer) sia per il primo avvio dell'AppImage
(AppImage → `~/sagra`).

---

## Percorsi di output

Ogni script scrive il risultato in una cartella `dist/` **relativa alla
propria posizione**, non alla directory da cui viene lanciato. Puoi
quindi spostare il progetto ovunque, lanciarlo da qualsiasi cartella o
richiamarlo tramite un symlink nel `PATH`: l'output finisce sempre
accanto allo script.

| Cartella | Contenuto |
|---|---|
| `<canale>/<variante>/dist/` | il file finale da distribuire |
| `<canale>/<variante>/build/` | materiale intermedio e strumenti scaricati (`appimagetool`, `AppDir`, log di compilazione) |

Nessuno dei due va versionato: il `.gitignore` nella radice li esclude
per tutte e quattro le varianti, insieme al contenuto di `appdata/`
(che viene ricopiato a ogni build dalla cartella sorgente).

---

## Backup automatico (incluso)

Entrambi i canali di distribuzione includono il sistema di backup con
restic verso chiavetta USB e Dropbox.

**Windows (installer Inno Setup)**
Durante l'installazione compare la casella *"Installa il backup
automatico"* (non selezionata per impostazione predefinita). Se
spuntata, gli script finiscono in `{app}\backup` e il setup lancia
`Install-SagraBackup.ps1`, che crea l'attivita' pianificata ogni 10
minuti. Su Windows restic usa VSS in modo nativo
(`--use-fs-snapshot`), quindi copia il database anche se aperto.

**Linux (AppImage)**
Gli script sono inclusi nell'AppImage. Per installarli:

```bash
./GestioneStandGastronomico-x86_64.AppImage --backup-setup
./GestioneStandGastronomico-x86_64.AppImage --backup-status
```

Il primo comando installa gli script, crea la configurazione gia'
compilata con la cartella dati corretta per la variante, e attiva il
timer systemd. Su Linux lo script prova prima uno snapshot del
filesystem (Btrfs/ZFS/LVM) e, se non disponibile, mette brevemente in
pausa l'applicazione per ottenere una copia coerente.

**Prerequisiti installati automaticamente**
Non serve preparare nulla a mano: gli installer verificano la presenza
di `restic` (e `rsync` su Linux) e, se manca, lo installano da soli.

- **Windows**: `winget install --exact --id restic.restic --scope Machine`
  (lo scope Machine e' necessario perche' l'attivita' gira come SYSTEM).
  Se winget installa restic in modalita' "portable" senza creare
  l'alias nel PATH, l'installer trova comunque l'eseguibile e ne
  registra il percorso completo nella configurazione.
- **Linux**: rileva la distribuzione e usa `apt`, `dnf`, `pacman`,
  `zypper`, `apk` o `eopkg`. Se manca il gestore o i privilegi, stampa
  il comando esatto da eseguire a mano.

`rclone` (necessario solo per Dropbox) viene proposto con una domanda:
rispondendo no, il backup su Dropbox resta disattivato e quello su
chiavetta funziona comunque.

Dettagli completi nel README dentro la cartella `backup`.

---

## Come funziona l'AppImage a runtime

Sul PC Linux serve **Wine a 32 bit**:

```bash
sudo dpkg --add-architecture i386
sudo apt update
sudo apt install wine32 wine
```

Al primo avvio l'AppImage:
- crea un prefix Wine dedicato (`WINEARCH=win32`), separato per variante
- copia e registra i runtime VB6 con `regsvr32`
- copia il contenuto dell'app in una **cartella dati esterna**:
  - `default` → `~/sagra`
  - `sant-agostino` → `~/sagra-santagostino`
- mappa quella cartella dentro Wine come `C:\SAGRA` (o
  `C:\SAGRA_SANT-AGOSTINO`), così funziona anche con percorsi assoluti
  hardcoded nell'applicazione

Ad ogni avvio successivo:

| Tipo file | Comportamento |
|---|---|
| `.exe .dll .ocx .tlb .chm` | sempre riallineati alla versione nell'AppImage |
| `.ini`, database, archivi, log, tutto il resto | copiati solo se mancanti, **mai sovrascritti** |

Così aggiornare l'AppImage aggiorna il programma senza toccare i dati
della sagra. Per cambiare cartella dati:

```bash
SAGRA_HOME=/mnt/dati/sagra ./GestioneStandGastronomico-x86_64.AppImage
```

Backup: basta copiare `~/sagra`.

---

## Flusso di lavoro tipico

**Installer Windows**
1. Prepari/aggiorni l'installazione in `C:\SAGRA`
   (o `C:\SAGRA_SANT-AGOSTINO`)
2. Doppio click su `inno/<variante>/build.bat`
3. L'installer esce in `inno/<variante>/dist/`

**AppImage Linux**
1. Sul PC Linux (anche da sessione live) monti la partizione Windows
2. Lanci `appimage/<variante>/build-*.sh`, che trova da solo la
   cartella dell'app oppure la prende dal percorso che gli passi
3. L'AppImage esce in `appimage/<variante>/dist/`
4. La copi sul PC della sagra, `chmod +x` e la avvii: al primo avvio i
   dati finiscono in `~/sagra` e negli aggiornamenti successivi
   vengono preservati

In entrambi i casi il sistema di backup viene distribuito insieme
all'applicazione (vedi sezione "Backup automatico").
