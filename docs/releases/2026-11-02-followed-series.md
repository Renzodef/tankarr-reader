# Serie seguite e avvisi dei nuovi capitoli

- Pulsante Segui nella scheda, scelta condivisa sullo stesso account e filtro
  delle serie seguite nella libreria.
- Registrazione APNs nativa e richiesta di permesso al primo Segui, con
  collegamento alle impostazioni se negato. Nessun watcher o polling nell'app.
- Gli avvisi aprono la serie soltanto per il server/account corrispondente;
  nessun URL o comando del payload viene eseguito.
- Gateway con outbox persistente, webhook Tankarr autenticato, baseline del
  catalogo al momento del Segui e deduplica dei capitoli importati.
- Supporto agli identificativi del provider contenenti punti, mantenendo il
  rifiuto di percorsi, query e traversal; questi ID valgono anche per i bookmark.
- Privacy aggiornata per la registrazione del dispositivo e la selezione di serie.

La capability Push Notifications richiede un profilo App Store aggiornato; il
server richiede una chiave APNs separata dalla chiave App Store Connect.
Senza di essa il Segui funziona e viene segnalata la mancata configurazione
push: non viene dichiarata una consegna non verificata. Per il primo avviso
reale servono inoltre una build firmata sul telefono e il permesso iOS.

Distribuzione: il push pertinente su main attiva la verifica completa e il
caricamento TestFlight sul runner Mac. Non seleziona né ritira versioni App Store
in revisione. Prima di un nuovo invio pubblico aggiornare le risposte privacy
App Store Connect per gli identificatori e il contenuto di lettura inviati al
server configurato, usati solo per funzionalità dell'app e senza tracciamento.
