# Copertine e lettura

Le copertine hanno una coda cancellabile con due richieste attive e una
sessione di rete separata da catalogo, segnalibri e pagine. Scorrere via da
una cella annulla la sua attesa prima che inizi il timeout HTTP. Errori
temporanei 429/502/503/504 e timeout vengono ritentati al massimo due volte.
Errori di autenticazione, risorse mancanti e redirect restano errori.

La cache delle copertine conserva fino a 64 MiB su disco, separati per
identità server/account e con scadenza di cinque minuti. Le miniature
decodificate usano la cache in memoria esistente da 32 MiB. Aggiornare il
catalogo conserva le immagini valide e riprova quelle fallite. La disconnessione
cancella la cache dell'account e le risposte tardive non la ricreano.
ImageIO prepara le miniature fuori dal thread principale senza decodificare
in memoria la copertina a piena risoluzione.

Le tre pagine consultate di recente possono essere riutilizzate in memoria,
con un limite di 64 MiB e azzeramento al cambio sessione. La preparazione
delle pagine per la visualizzazione è asincrona. Il debounce del cursore
passa da 150 a 40 ms. Non viene precaricato un volume intero.

Il manifest privacy dichiara l'accesso alle date dei soli file della cache
nel contenitore dell'app, secondo la
[documentazione Apple](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).

Verifica automatica: limiti di concorrenza, annullamento in coda, cache persistente,
isolamento account, scadenza, spazio massimo, errori transitori, autenticazione
e redirect. La stessa app iOS è disponibile sui Mac Apple Silicon come app
progettata per iPad/iPhone. Fluidità, download in background e navigazione
vanno verificati sulla nuova build TestFlight sui dispositivi reali.
