# Tankarr Reader 1.0.0 (9): download in background

- Sorgenti: [`0394f4b`](https://github.com/Renzodef/tankarr-reader/commit/0394f4b52e19cc81a52395a314ed0d369c9c58e9).
- [Pipeline di verifica, firma e distribuzione](https://github.com/Renzodef/tankarr-reader/actions/runs/41271745463).
- Questo aggiornamento supera il limite dei download in primo piano della build 8.

## Comportamento

La selezione completa viene salvata prima di iniziare i trasferimenti, compresi
i capitoli che devono ancora partire. Mettere il Reader in background non
cancella la coda: i download reali sono affidati al servizio di rete di iOS.
Alla riapertura dopo una terminazione, il Reader recupera la selezione e
scarica soltanto le pagine mancanti, senza dover scegliere di nuovo i capitoli.

La chiusura forzata interrompe i trasferimenti di iOS fino alla successiva
apertura dell'app. Rete, risparmio energetico e pianificazione di iOS possono
ritardare il lavoro in background; non è una garanzia di velocità continua.

Offline sospende la coda conservandola. La pausa esplicita di un libro conserva
le pagine già scaricate ma lo rimuove dalla coda attiva. Rimuovere un libro,
una serie o tutti i download annulla gli intenti prima dei task: risposte
tardive e riapertura non devono ricreare copie cancellate volontariamente.

Password nel Portachiavi e dati locali privati usano la protezione fino al
primo sblocco del dispositivo, così possono essere utilizzati anche dopo il
successivo blocco dello schermo. Nessuna credenziale è scritta nella coda.
Dettagli: [BACKGROUND-DOWNLOADS.md](../BACKGROUND-DOWNLOADS.md).

## Verifica sul commit distribuito

Il 1 novembre 2026, tutti riusciti:

- 94 test Python di tooling, distribuzione e asset.
- 56 test Swift del core: persistenza dell'intera selezione, batch limitati,
  deduplica, isolamento account, risposte obsolete dopo cancellazione e
  interruzione fra salvataggio di una pagina e aggiornamento della coda.
- 11 test UI su iPhone 17: conclusi alle **05:19:52 CET**, Europe/Rome.
- 11 test UI su iPad A16: conclusi alle **05:32:53 CET**, Europe/Rome.

Tre nuove prove per ciascun simulatore usano un server HTTP locale con pagine
originali e trasferimenti rallentati, la sessione background reale di iOS e
il Portachiavi del simulatore: continuazione dopo Home, terminazione e
riapertura senza riselezionare la coda, rimozione durante un download senza
ricomparsa dopo il rilancio. La prova di riapertura controlla anche che una
pagina già salvata non venga richiesta di nuovo. Le otto prove esistenti
coprono lettura, segnalibri, filtri offline, intervalli, navigazione e copertine.

Queste prove sono su simulatori iPhone/iPad; non attestano una sessione su
iPhone fisico con schermo bloccato. Nessun server o contenuto dell'utente è
stato usato per i test.

## Distribuzione

Distribuita al gruppo TestFlight interno il **1 novembre 2026 alle 05:40 CET**
(Europe/Rome). Archivio, esportazione e upload riusciti; pipeline conclusa
con successo. Stato Apple riletto: `VALID`, `IN_BETA_TESTING`. Note di rilascio
italiane e inglesi pubblicate e verificate alle **05:41 CET**.

Per installarla: TestFlight → Tankarr Reader → **Aggiorna**, versione **1.0.0 (9)**.
L'invio pubblico già esistente non è stato sostituito da questa distribuzione
TestFlight interna.
