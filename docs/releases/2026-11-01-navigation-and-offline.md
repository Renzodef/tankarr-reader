# Navigazione dei capitoli, segnalibri e offline automatico

- Sorgenti: [`2f5494c`](https://github.com/Renzodef/tankarr-reader/commit/2f5494caf6b0f9d28e3e346dbd89620c82016a40).
- Correzioni iPad: [`e23f29c`](https://github.com/Renzodef/tankarr-reader/commit/e23f29c0c6c9aafe1bf82e2ed22a0d30771a9252).
- [Pipeline iPhone/iPad e TestFlight](https://github.com/Renzodef/tankarr-reader/actions/runs/41333905579).

## Comportamento

La barra delle pagine segue il verso orizzontale scelto: RTL parte da destra,
LTR da sinistra; la lettura verticale mantiene la barra da sinistra.
Avanti dall'ultima pagina apre il capitolo successivo alla prima pagina;
indietro dalla prima apre il precedente all'ultima, indipendentemente dalla
posizione locale precedente. Ogni capitolo ha nuovi task, immagini e preferenze.

I capitoli adiacenti sono quelli indicati dal server, anche offline: il filtro
dei download non deve saltare un capitolo mancante. Una copia incompleta non è
leggibile offline. Quando manca il download o si raggiunge l'inizio/fine della
serie, compare un avviso e resta aperto il capitolo corrente.
In continuo un trascinamento iniziato sul bordo e rilasciato oltre il bordo
attiva la stessa navigazione; raggiungere il bordo per inerzia non basta.

Nella scheda serie **Riprendi dal segnalibro** usa la pagina esplicita salvata,
anche se la posizione locale è diversa. Se il capitolo segnato manca offline,
compare un avviso senza richieste di rete. In assenza di segnalibro la scheda
spiega dove crearlo: icona Segnalibro nel lettore, poi Salva segnalibro.

Con copie complete disponibili, la perdita di rete o un errore di raggiungibilità
attiva **Offline automatico**. L'app riprova al ritorno della rete o in primo
piano; non ci sono timer di riconnessione. Il controllo della rete usa gli eventi
di [NWPathMonitor](https://developer.apple.com/documentation/network/nwpathmonitor).
Offline scelto a mano rimane invece attivo finché si preme **Torna online** o
il pulsante Wi-Fi barrato. Errori di autenticazione, TLS o del server restano
visibili. Coda download e modifiche ai segnalibri restano persistenti.

## Verifiche e distribuzione

- Pre-push: **94 test Python**, asset e manifest privacy riusciti.
- Core: **68 test Swift**, zero errori.
- Simulatore iPhone: cambio capitolo online, ripresa dal segnalibro che prevale
  sulla posizione locale, capitolo/segnalibro non scaricato senza richieste al
  server, capitoli adiacenti offline, errore di socket con ritorno automatico
  online, conservazione dell'offline manuale, trascinamento fisico della barra
  RTL/LTR/verticale e trascinamento oltre il bordo nel continuo: riusciti.
- Suite completa iPhone 17: **16 test UI, zero errori**, conclusa il 1 novembre
  2026 alle **19:15:47 CET** (Europe/Rome).
- Prove mirate iPad A16 (anche in finestra stretta): cursore RTL/LTR/verticale,
  continuo, capitoli, segnalibri, offline automatico/manuale e riconnessione: riuscite.
  La prova di foreground usa un cambio reale verso Impostazioni: Home da solo
  può lasciare il lettore in primo piano nella modalità a finestre.
- Suite completa iPad A16: **16 test UI, zero errori**, conclusa il 1 novembre
  2026 alle **19:35:29 CET**. Il job di verifica è terminato con successo alle
  **19:35:36 CET**.
- Distribuzione: **1.0.0 (12)** caricata senza errori alle **19:37:30 CET**;
  gruppo TestFlight interno aggiornato alle **19:39:38 CET**. La pipeline è
  conclusa con successo alle **19:39:44 CET**.
- Verifica indipendente su App Store Connect: build valida, stato
  **IN_BETA_TESTING**, note `it` ed `en-US` salvate e rilette il 1 novembre
  2026 alle **19:40 CET**.

La prima pipeline è stata fermata prima della distribuzione: le nuove prove
su iPad hanno rilevato l'interferenza dei controlli della finestra con la barra
superiore e il cursore. I comandi ora usano la barra nativa; il titolo resta
visibile anche nelle finestre strette e il cursore è sopra ai pulsanti pagina,
lontano dall'angolo di ridimensionamento. Il test del cursore verifica anche
che la larghezza della finestra resti invariata durante il trascinamento.

Il backend Tankarr non richiede modifiche. Il push pubblica sul gruppo interno
TestFlight dopo i test, senza sostituire la versione pubblica in revisione.
