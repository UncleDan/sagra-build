# Backup dati sagra su Windows — restic + VSS

Sostituto di Cobian Reflector: backup ogni 10 minuti della cartella
dati, con due destinazioni indipendenti (chiavetta USB e Dropbox).

## Rispetto a Cobian Reflector

| | Cobian Reflector | Questo |
|---|---|---|
| File aperti | VSS | VSS (`--use-fs-snapshot`, nativo in restic) |
| Pianificazione | scheduler interno | Utilità di pianificazione |
| Formato | archivi 7z | repository restic deduplicato |
| Storico | archivi separati | snapshot navigabili |
| Verifica integrità | — | `restic check` |
| Destinazioni | copia su ciascuna | due repository indipendenti |

Il vantaggio principale è la **deduplica a blocchi**: 144 backup al
giorno occupano pochissimo, perché tra un backup e l'altro del
database cambia solo una frazione dei blocchi. Con archivi 7z separati
ogni backup pesa quanto l'intero database.

La compressione è impostata su `off` per velocità
(`$ResticCompression` nel file di configurazione); la deduplica
funziona comunque.

## Differenza rispetto alla versione Linux

Su Linux non esiste VSS, quindi lo script mette brevemente in pausa il
processo dell'applicazione (`SIGSTOP`) per ottenere una copia coerente.

Su Windows non serve: restic crea da sé lo snapshot VSS e legge i file
da lì, quindi l'applicazione **non viene mai toccata** e i file aperti
in esclusiva vengono copiati comunque.

VSS richiede privilegi amministrativi: l'attività pianificata è quindi
configurata per girare come SYSTEM con privilegi elevati. Se lo script
viene lanciato senza elevazione, prosegue disattivando VSS e lo annota
nel log.

## Le due destinazioni

- **Chiavetta USB** — funziona offline. Cercata per **etichetta di
  volume**, non per lettera di unità: la lettera cambia a seconda della
  porta, l'etichetta no. Se non è inserita, quel backup viene saltato e
  annotato, senza compromettere l'altro.
- **Dropbox** (via `rclone`) — funziona fuori sede. Se manca la rete,
  vale il contrario.

Basta che una delle due riesca perché l'esecuzione sia considerata
riuscita.

## Installazione

```powershell
winget install restic.restic
winget install Rclone.Rclone      # solo se vuoi Dropbox
```

Riapri PowerShell (perché il PATH venga aggiornato), poi **come
amministratore**:

```powershell
.\Install-SagraBackup.ps1
```

Lo script copia i file in `%ProgramData%\SagraBackup`, chiede la
password del repository, ne limita l'accesso a SYSTEM e Administrators,
e crea l'attività pianificata.

Poi:

1. Adatta la configurazione:
   ```powershell
   notepad "$env:ProgramData\SagraBackup\config.ps1"
   ```
   In particolare `$SagraHome` e `$EtichettaUSB`.

2. Solo per Dropbox:
   ```powershell
   rclone config
   ```
   Crea un remote di tipo `dropbox` chiamato `dropbox`.

   > **Attenzione**: l'attività gira come SYSTEM, che ha un profilo
   > diverso dal tuo e quindi non vede la tua configurazione rclone.
   > Copia `%APPDATA%\rclone\rclone.conf` in
   > `C:\Windows\System32\config\systemprofile\AppData\Roaming\rclone\`,
   > oppure modifica l'attività per girare col tuo utente (spuntando
   > "Esegui con i privilegi più elevati", che serve comunque per VSS).

3. Prova subito:
   ```powershell
   Start-ScheduledTask -TaskName "Backup Sagra"
   Get-Content "$env:ProgramData\SagraBackup\backup.log" -Tail 20 -Wait
   ```

> **La password del repository è indispensabile.** Senza, i backup non
> sono recuperabili in nessun modo. Annotala anche fuori da questo PC.

## Uso quotidiano

```powershell
Get-ScheduledTask -TaskName "Backup Sagra" | Get-ScheduledTaskInfo
Get-Content "$env:ProgramData\SagraBackup\backup.log" -Tail 20
```

## Ripristino

```powershell
cd "$env:ProgramData\SagraBackup"

.\Restore-SagraBackup.ps1 -Azione elenco
.\Restore-SagraBackup.ps1 -Azione elenco -Destinazione cloud
.\Restore-SagraBackup.ps1 -Azione ripristina -Snapshot latest
.\Restore-SagraBackup.ps1 -Azione ripristina -Snapshot a1b2c3d4 -Destinazione cloud -Cartella "D:\recupero"
.\Restore-SagraBackup.ps1 -Azione verifica
```

Il ripristino scrive in una cartella separata e non sovrascrive i dati
in uso.

## Retention

Configurabile in `config.ps1`. Impostazione iniziale:

| Regola | Valore |
|---|---|
| `KeepLast` | 72 (≈12 ore a 10 min) |
| `KeepHourly` | 48 |
| `KeepDaily` | 14 |
| `KeepWeekly` | 8 |

Il `forget` gira a ogni backup (è leggero). Il `prune`, che recupera
davvero lo spazio ma è pesante, gira al massimo una volta ogni 24 ore
(`$OreTraPrune`).

## Note

- Un mutex globale impedisce esecuzioni sovrapposte: se un backup è
  ancora in corso, quello successivo viene saltato e annotato.
- I file di lock di Access (`.ldb`, `.laccdb`) sono esclusi dal
  backup; la loro presenza viene annotata nel log.
- Il repository è lo stesso formato su Windows e Linux: un repository
  restic creato su Windows si legge da Linux e viceversa.
