# Backup dati sagra — restic verso chiavetta USB e Dropbox

Equivalente Linux di Cobian Reflector + VSS: backup ogni 10 minuti
della cartella dati, con due destinazioni indipendenti.

Non è vincolato a nessun filesystem: funziona su ext4, Btrfs, XFS,
qualsiasi cosa.

## L'equivalente di VSS su Linux

Esistono meccanismi analoghi, ma dipendono dal filesystem. Lo script
li prova in ordine e ripiega automaticamente (opzione `METODO` in
config):

| Metodo | Filesystem | Privilegi | Note |
|---|---|---|---|
| Snapshot Btrfs | Btrfs (subvolume) | root | istantaneo, spazio iniziale nullo |
| Snapshot ZFS | ZFS | root | letto da `.zfs/snapshot` |
| Snapshot LVM | qualsiasi su LVM | root | serve spazio libero nel volume group |
| **Pausa applicazione** | **qualsiasi** | **nessuno** | fallback sempre disponibile |

`METODO="auto"` (predefinito) tenta lo snapshot e, se non è
disponibile, usa la pausa senza far fallire il backup. Con
`METODO="snapshot"` invece l'assenza di snapshot è un errore, e con
`METODO="pausa"` si forza sempre il metodo semplice.

Il limite pratico degli snapshot è che richiedono root (direttamente o
via `sudo` senza password), mentre il timer gira come utente normale.
Su un PC da sagra il metodo a pausa è spesso la scelta più sensata:
zero configurazione, zero privilegi, e come mostrato sotto è anche più
solido di VSS su un database Jet.

## Come sostituisce VSS

VSS congela il volume per ottenere una copia coerente. Qui si ottiene
lo stesso risultato — anzi, un po' meglio — mettendo brevemente in
pausa il processo dell'applicazione:

1. `SIGSTOP` al processo Wine dell'applicazione
2. copia incrementale in staging con `rsync` (poche decine di ms)
3. `SIGCONT`: l'applicazione riparte
4. con calma, `restic` salva lo staging nei due repository

L'applicazione resta ferma solo per il passo 2. Misurato su dati di
prova: **~50 ms**, impercettibile per chi sta battendo le comande.

Il vantaggio rispetto a VSS: con un database Jet/Access, VSS produce
una copia solo *crash-consistent* (Jet non ha un VSS writer). Qui
invece l'applicazione è davvero quiescente nell'istante della copia.

Se lo script viene interrotto a metà, un `trap` garantisce comunque il
`SIGCONT`: l'applicazione non può restare congelata.

## Le due destinazioni

Sono due repository restic **indipendenti**, non una copia dell'altro:

- **Chiavetta USB** — funziona offline. Se la chiavetta non è
  inserita, quel backup viene saltato e registrato nel log, senza
  compromettere l'altro.
- **Dropbox** (via `rclone`) — funziona fuori sede. Se manca la rete,
  vale il contrario.

Basta che una delle due riesca perché l'esecuzione sia considerata
riuscita.

## Perché restic

- **Deduplica a blocchi**: 144 backup al giorno occupano pochissimo,
  perché tra un backup e l'altro del database cambia solo una
  frazione dei blocchi.
- **Versioning nativo**: ogni backup è uno snapshot navigabile, si può
  tornare a un momento preciso della serata.
- **Integrità verificabile**: `restic check` valida l'intero
  repository.
- **Backend rclone**: parla con Dropbox senza client ufficiale.

La compressione è impostata su `off` per velocità (`RESTIC_COMPRESSION`
nel file di configurazione); la deduplica funziona comunque.

## Installazione

```bash
sudo apt install restic rsync rclone     # o equivalente della distro
chmod +x install.sh
./install.sh
```

L'installazione non richiede root: usa `systemd --user`, attiva il
timer e imposta il *linger* così il backup gira anche a sessione
chiusa.

Poi:

1. Adatta la configurazione:
   ```bash
   nano ~/.config/sagra-backup/config
   ```
   In particolare `SAGRA_HOME` e `REPO_USB` (percorso sulla chiavetta).

2. Solo per Dropbox, una volta sola:
   ```bash
   rclone config
   ```
   Crea un remote di tipo `dropbox` chiamato `dropbox`.

3. Prova subito:
   ```bash
   systemctl --user start sagra-backup.service
   tail -f ~/.local/state/sagra-backup/backup.log
   ```

> **La password del repository è indispensabile.** Senza, i backup non
> sono recuperabili in nessun modo. Annotala anche fuori da questo PC.

## Uso quotidiano

```bash
systemctl --user list-timers sagra-backup.timer   # prossima esecuzione
tail -20 ~/.local/state/sagra-backup/backup.log   # cosa è successo
```

## Ripristino

```bash
sagra-restore.sh elenco usb              # elenca gli snapshot
sagra-restore.sh elenco cloud
sagra-restore.sh ripristina latest usb   # ripristina l'ultimo
sagra-restore.sh ripristina a1b2c3d4 cloud ~/recupero
sagra-restore.sh verifica usb            # controlla l'integrità
```

Il ripristino scrive in una cartella separata (default
`~/sagra-ripristino`), non sovrascrive i dati in uso. Per rimettere in
servizio i dati recuperati: chiudi l'applicazione, sposta l'attuale
cartella dati come copia di sicurezza, poi metti al suo posto quelli
ripristinati.

## Retention

Configurabile in `config`. Impostazione iniziale:

| Regola | Valore |
|---|---|
| `KEEP_LAST` | 72 (≈12 ore a 10 min) |
| `KEEP_HOURLY` | 48 |
| `KEEP_DAILY` | 14 |
| `KEEP_WEEKLY` | 8 |

Il `forget` gira a ogni backup (è leggero). Il `prune`, che recupera
davvero lo spazio ma è pesante, gira al massimo una volta ogni 24 ore
(`ORE_TRA_PRUNE`).

## Note

- Un `flock` impedisce esecuzioni sovrapposte: se un backup è ancora
  in corso, quello successivo viene saltato e annotato.
- I file di lock di Access (`.ldb`, `.laccdb`) sono esclusi dal
  backup; la loro presenza viene annotata nel log, così sai quali
  archivi sono stati presi con il database aperto.
- Il servizio gira con priorità bassa (`Nice`, I/O idle) per non
  rallentare l'applicazione durante il servizio.
- Il log ruota automaticamente oltre la dimensione impostata.
