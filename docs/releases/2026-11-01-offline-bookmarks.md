# Segnalibri offline con sincronizzazione al ritorno online

- Sorgenti: [`d52a3c7`](https://github.com/Renzodef/tankarr-reader/commit/d52a3c76722618eb79e32d374eef78df09c161d3).
- [Pipeline di verifica e TestFlight](https://github.com/Renzodef/tankarr-reader/actions/runs/41277428250).

## Comportamento

Salvare, spostare e rimuovere un segnalibro funziona anche offline dopo la prima
conferma del permesso da parte del server. Il lettore e la lista dei segnalibri
mostrano le modifiche in attesa. La scrittura locale precede quella remota:
chiudere l'app o perdere la connessione non perde la modifica.

Riaprire l'app online, ricollegarsi, tornare in primo piano online o aggiornare
i segnalibri riprova gli elementi pendenti. La modalità offline scelta a mano
resta attiva finché non viene disattivata. Un errore lascia gli elementi in
attesa: una vecchia lista remota non può far riapparire una rimozione locale.

Il file atomico `bookmarks-sync.json`, separato per identità server e account,
contiene la fotografia remota, il permesso verificato e le modifiche pendenti.
Una conferma può rimuovere soltanto l'UUID della modifica inviata; non quello
di una modifica successiva alla stessa serie. I vecchi `bookmarks.json` vengono
letti senza perdere i segnalibri. Lo stato è privato, protetto dal dispositivo
ed escluso dal backup iCloud insieme all'archivio offline.

Per ciascuna serie l'ultima modifica esplicita locale viene inviata al ritorno
online e sostituisce il segnalibro condiviso di quella serie. Le altre serie
restano invariate. Il semplice cambio pagina continua a salvare soltanto la
posizione locale; la demo continua a non contattare il server.

Eliminare i download conserva le modifiche pendenti ai segnalibri. Disconnettere
l'account le elimina dopo una conferma che lo specifica. Le risposte appartenenti
alla sessione precedente non possono ricreare il journal dopo la disconnessione.
Nessun polling, servizio aggiuntivo o cambiamento al backend Tankarr.

## Verifica

- Pre-push: **94 test Python**, asset e manifest privacy riusciti.
- Mac, test core: **64 test Swift** riusciti, compresi 8 nuovi casi di persistenza,
  conferme ritardate, rimozioni, isolamento, migrazione e permessi.
- iPhone 17, server HTTP di prova: segnalibro offline, chiusura e riapertura,
  errore 503, riapertura online con sincronizzazione automatica, rimozione offline
  e successiva conferma remota. **1 test UI riuscito in 82,9 secondi**.
- Suite completa iPhone 17: **13 test UI, zero errori**, conclusa il 1 novembre
  2026 alle **06:49:40 CET** (Europe/Rome).
- Suite completa iPad: **13 test UI, zero errori**, conclusa alle **07:05:03 CET**.
- Archivio ed esportazione riusciti; upload Apple completato alle **07:06:55 CET**.
- **1.0.0 (11)** distribuita al gruppo TestFlight interno alle **07:08:59 CET**.
  Stato Apple `VALID` / `IN_BETA_TESTING` e note italiane/inglesi verificati via API.

Nessuna modifica alla versione pubblica già in revisione su App Store.
