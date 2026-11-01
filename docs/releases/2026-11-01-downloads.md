# Tankarr Reader 1.0.0 (8)

Distribuita al gruppo TestFlight interno il **1 novembre 2026 alle 02:00 CET**
(Europe/Rome). Apple: `VALID`, `IN_BETA_TESTING`. Note italiane e inglesi
pubblicate e rilette per verificarne il contenuto.

- Sorgenti: [`e9c971d`](https://github.com/Renzodef/tankarr-reader/commit/e9c971d9efea0a402345f0ee318a79da77415188).
- [Pipeline di verifica, firma e distribuzione](https://github.com/Renzodef/tankarr-reader/actions/runs/41257363683): riuscita sul Mac dedicato.
- 93 test Python, 50 test Swift e 8 test UI su ciascuna famiglia, iPhone e iPad: tutti riusciti.
- Prima del push: tre prove UI mirate su iPhone e controllo visivo delle copertine e dei segnalibri offline.

## Comandi aggiunti

- **Modalità offline**, icona Wi-Fi barrata in alto: mostra solo serie con
  almeno un libro completo e i segnalibri di quelle serie. Le copie dei
  segnalibri e le copertine persistono nell'archivio privato per account/server.
  Un segnalibro che punta a un capitolo non scaricato apre la serie, con una
  spiegazione, invece di avviare una lettura in rete.
- **Download della serie**: menu **Scarica intervallo…**, con selettori Da/A
  inclusivi nell'ordine del catalogo, **Scarica dal segnalibro alla fine** e
  **Rimuovi download della serie**. Il capitolo segnato è incluso; un segnalibro
  assente o non più presente nel catalogo non avvia un download totale.
- **Download**: cestino in alto per cancellare tutte le copie locali e la coda
  dell'account, con conferma. La cancellazione di una serie mantiene le altre.
- **Torna alla serie** nel lettore, anche arrivando da Download o Segnalibri.
- Copertine con proporzioni fisse e allineamento superiore; spazio uniforme
  per i titoli a una o due righe.

I test coprono intervalli invertiti/inesistenti, capitoli speciali, segnalibri
obsoleti o di altre serie, isolamento fra account, persistenza dopo riapertura,
filtri sui download completi e risposte tardive dopo la cancellazione.

I download richiedono l'app aperta. Attivare Offline mette in pausa i
trasferimenti; modificare i segnalibri condivisi richiede una connessione.
Le cancellazioni agiscono sulle copie locali. Nessuna modifica al server o
alle code Tankarr, nessuna sostituzione dell'invio App Store esistente.
