# Download e coda persistente su iOS

Il download reale usa una sola `URLSessionConfiguration.background` per account,
con identificatore stabile, delegate e `sessionSendsLaunchEvents = true`.
`isDiscretionary = false` dà precedenza alla selezione avviata dall'utente; iOS
resta libero di differirla per rete, energia e richieste create in background.
Nessun audio silenzioso, timer keepalive o background mode improprio.

## Stato e ciclo di vita

- La selezione completa, nell'ordine del catalogo, viene scritta atomicamente in
  `.metadata/background-queue.json` prima di creare task. Contiene serie, libri,
  token e pagine mancanti, senza URL o credenziali.
- Anche il recupero dei metadati del libro è un download background. I libri
  non ancora iniziati non dipendono da una `Task` Swift rimasta in memoria.
- Batch fino a 64 richieste, con due connessioni per host. Evita il risveglio
  dell'app dopo ogni singola pagina; l'ammissione si riduce se manca spazio.
- In background iOS gestisce la rete in un altro processo. Il delegate sposta
  subito i file temporanei, poi valida risposta, dimensione e immagine. Lo store
  verifica spazio e token, salva la pagina/checksum e infine aggiorna la coda.
- Il completion handler UIKit viene chiamato sul main actor soltanto dopo
  l'elaborazione degli eventi, le scritture e l'eventuale nuovo batch.
- Dopo una terminazione si riassocia la sessione agli stessi task e si rilegge
  la coda. Se iOS ha annullato i task per chiusura forzata, vengono ricreati alla
  riapertura. Una pagina salvata prima della scrittura della coda viene
  riconosciuta tramite manifest/checksum, senza riscaricarla.
- Un errore conserva la selezione e ferma i tentativi; il ritorno nell'app,
  la riconnessione o «Riprendi la coda» riprovano. Un'assenza di connettività
  iniziale è gestita da `waitsForConnectivity`.
- Offline conserva la coda sospesa; pausa esplicita di un libro conserva le
  pagine ma rimuove quel libro dalla coda attiva. Rimuovi serie/tutto annulla gli
  intenti prima dei task, così i callback tardivi non ricreano i download.

## Protezione

Password nel Portachiavi `AfterFirstUnlockThisDeviceOnly`; file offline e coda
protetti fino al primo sblocco, privati (0700/0600), esclusi dal backup. Questa
classe permette le scritture a schermo bloccato dopo il primo sblocco dal boot.
Le credenziali passano a iOS solo nell'header della richiesta autenticata;
non sono salvate nel nostro journal. TLS resta verificato, cookie/cache disabilitati.
Il background networking di Apple segue autonomamente i redirect: il client
rifiuta un file se l'URL finale differisce da quello richiesto. Il gateway
configurato deve servire direttamente gli endpoint delle pagine, senza redirect.

## Verifica

`BackgroundDownloadQueueTests` controlla coda dopo perdita del processo,
capitoli non iniziati, batch/deduplica, fencing dopo rimozione, interruzione fra
scrittura della pagina e della coda, isolamento account e richieste senza
credenziali negli URL. `BackgroundDownloadUITests` usa un server HTTP locale
nel runner XCTest e il vero servizio di download iOS: Home durante trasferimenti
lenti; chiusura/riapertura a metà di una selezione; lettura offline successiva.
Il simulatore è firmato ad hoc per provare anche il Portachiavi reale, senza
certificati o credenziali Apple. I test non contattano il server dell'utente.

Fonti Apple: [download background](https://developer.apple.com/documentation/foundation/downloading-files-in-the-background),
[sospensione e chiusura forzata](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/background(withidentifier:)).
