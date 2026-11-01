# Tankarr Reader per iOS

Client nativo SwiftUI per il gateway Tankarr Reader dell'self-hosted. iOS 17+,
iPhone e iPad; nessuna dipendenza esterna. Catalogo con ricerca e copertine,
elenco dei libri scaricati, lettura a pagine con zoom e scorrimento continuo,
verticale oppure orizzontale, con direzione selezionabile. Interfaccia italiana
e inglese.
L'ultima pagina letta resta sul dispositivo; i segnalibri vengono salvati sul
server Tankarr. Capitoli e volumi possono essere scaricati sul dispositivo per
la lettura offline. Nessuna modifica alla libreria,
nessuna ricerca/download sul server e nessuna chiave amministrativa nell'app.

La demo inclusa usa le stesse schermate del lettore con tre racconti e immagini
originali, senza rete o account. I progressi demo sono separati da quelli dei
server. Anche i segnalibri demo sono locali. Privacy e assistenza sono accessibili
da Connessione; i dati di lettura locali possono essere cancellati separatamente.

## Opzioni di lettura

Il pulsante **Opzioni di lettura** nel lettore consente di scegliere:

- il formato: **Automatico**, **A pagine** o **Scorrimento continuo**;
- l'asse: **Automatico**, **Verticale** o **Orizzontale**;
- la direzione orizzontale: **Automatico**, **Sinistra → destra** o **Destra → sinistra**.

Direzione e formato automatici seguono le indicazioni del server. L'asse
automatico usa il verticale in continuo e l'orizzontale a pagine, conservando il
comportamento della build 5. Un volume dichiarato webtoon si apre quindi in
continuo verticale. In verticale la scelta destra/sinistra è disabilitata; torna
disponibile scegliendo l'orizzontale. Le preferenze sono salvate sul dispositivo
per volume e server, restano dopo la riapertura e sono separate da quelle della
demo. L'aggiornamento conserva direzione e formato già scelti; il nuovo asse
parte da Automatico. Cambiare modalità mantiene la pagina corrente.

**A pagine** offre zoom con due dita e doppio tocco. Senza zoom, gli scorrimenti
cambiano pagina lungo l'asse scelto; in verticale si usano gesti su/giù e frecce
su/giù, in orizzontale vale il verso di lettura scelto. Con lo zoom attivo, il
trascinamento sposta l'immagine senza cambiare pagina.

**Scorrimento continuo** mostra tutte le pagine del capitolo in sequenza:
dall'alto verso il basso in verticale, oppure da sinistra a destra o da destra a
sinistra in orizzontale. Le immagini vengono caricate man mano che servono e
quelle lontane dalla posizione corrente vengono liberate per contenere l'uso di
memoria. Lo zoom resta disponibile nel formato a pagine. La pagina visibile già
caricata aggiorna la posizione locale ed è quella proposta dal menu Segnalibro;
salvare il segnalibro resta un'azione esplicita.

## Lingua dell'app

In **Connessione → Lingua dell'app** si può scegliere **Sistema**, **Italiano** o
**English**. Sistema è l'impostazione iniziale: sceglie la prima lingua supportata
(italiano o inglese) nell'elenco preferenze di iOS, oppure l'inglese se non ne
trova una. Il cambio si applica
subito e viene ricordato sul dispositivo, senza perdere connessione o posizione
di lettura. Cambia i comandi e i messaggi dell'app; non traduce titoli, libri o
racconti demo, che restano nella lingua dei contenuti.

## Segnalibri e ripresa

Il pulsante **Segnalibri** nella libreria mostra i segnalibri condivisi con
Tankarr; **Riprendi lettura** apre la pagina salvata. Nel lettore, il menu
**Segnalibro** salva la pagina visualizzata, sposta il segnalibro o lo rimuove.
Tankarr conserva un solo segnalibro per serie, condiviso tra lettori e dispositivi:
salvarlo in un altro volume della serie sostituisce il precedente.

Il cambio pagina ricorda automaticamente l'ultima posizione sul dispositivo;
aggiornare il segnalibro condiviso richiede un'azione esplicita, come nel sito
Tankarr. Aprire un volume riprende la posizione locale, se presente; altrimenti
usa il segnalibro del server. Aprirlo dall'elenco Segnalibri usa sempre la pagina
del segnalibro. Un errore di salvataggio viene mostrato: aggiorna l'elenco per
verificare lo stato prima di riprovare. Non ci sono scritture automatiche in coda.

Il gateway deve dichiarare `reading_state_writable: true` e offrire
`GET /v1/bookmarks`, `PUT/DELETE /v1/series/ID/bookmark`. Le scritture inviano
`X-Tankarr-Reader: 1`; PUT invia JSON e DELETE non ha un corpo.
Gli endpoint amministrativi restano inaccessibili.
I gateway precedenti continuano a offrire lettura e ripresa locale.

## Download sul dispositivo

Nell'elenco di una serie, la freccia accanto a un capitolo o volume avvia il
download locale. **Scarica tutti** mette in coda i libri della serie, uno alla
volta. Non avvia ricerche né acquisizioni sul server: copia soltanto pagine già
accessibili all'account lettore, usando gli stessi endpoint autenticati.

Il menu **Download della serie** in alto offre **Scarica intervallo…**, con due
menu **Da/A** inclusivi nell'ordine del catalogo, **Scarica dal segnalibro alla
fine** (include il capitolo segnato) e **Rimuovi download della serie**. Un
segnalibro assente o non più presente nel catalogo disabilita quel download;
non viene sostituito con un download di tutta la serie. I libri completi o già
in coda vengono saltati. La rimozione confermata annulla anche i trasferimenti
pendenti della sola serie, mantenendo quelli delle altre.

Il pulsante **Download** nella libreria mostra avanzamento, spazio occupato e
copie **Disponibili offline**. Si può mettere in pausa, riprendere o rimuovere
un download, oppure rimuoverli tutti con il cestino sempre visibile in alto,
dopo conferma. Una copia è pronta solo dopo il salvataggio
di tutte le pagine; i trasferimenti interrotti conservano quelle già ricevute e
**Riprendi** scarica soltanto le mancanti o danneggiate. Se la rete o il disco
falliscono, la coda si ferma senza ritentare indefinitamente. Dopo la chiusura
dell'app si riprendono manualmente i download incompleti; la coda non ancora
iniziata può essere selezionata di nuovo con **Scarica tutti**.

Tenere l'app aperta durante il trasferimento: non viene promesso il completamento
in background o a schermo bloccato. Il controllo dello spazio lascia almeno
256 MiB liberi e riserva spazio per la pagina temporanea. Le pagine sono limitate
a 64 MiB ciascuna, validate come immagini e salvate con checksum; non viene
caricato in memoria un intero volume.

Il tasto **Modalità offline** in alto mette in pausa i trasferimenti e mostra soltanto le serie
con almeno un libro completo e i segnalibri di quelle serie. Conserva le
copertine dei download e una fotografia dei segnalibri, separata per account e
server, anche dopo il riavvio. Se il capitolo segnato non è scaricato, la riga
lo spiega e apre la serie invece di tentare una lettura in rete. Il filtro si
aggiorna subito quando si cancellano le copie locali.

**Usa senza connessione** nella schermata Download attiva la stessa modalità;
toccare nuovamente il tasto in alto o **Ricollega al server** torna alla libreria
online. Il gesto di aggiornamento in modalità offline aggiorna solo i dati
locali. Le copie si leggono anche dopo aver chiuso e riaperto
l'app, in modalità a pagine o continua e con tutte le direzioni disponibili.
La pagina raggiunta continua a essere salvata localmente. Modificare i segnalibri
condivisi richiede la connessione e un salvataggio esplicito: non vengono accodate
scritture offline che potrebbero sovrascrivere quelle di altri dispositivi.
**Torna alla serie** nel lettore apre la scheda della serie anche arrivando da
Download o Segnalibri; **Chiudi libro** torna invece alla schermata precedente.

I download sono separati per identità del server e nome utente: LAN e HTTPS dello
stesso server condividono le copie, altri account no. I dati stanno in
Application Support, protetti dal dispositivo ed esclusi dai backup iCloud;
nessuna password viene scritta nei manifest. **Disconnetti** chiede conferma e
rimuove anche le copie dell'account. La cancellazione dei download non modifica
i file, i segnalibri o la libreria del server. Le copie sono una fotografia dei
libri: per aggiornarle dopo una sostituzione sul server, rimuoverle e scaricarle
nuovamente. La demo permette di provare gli stessi controlli senza credenziali.

Test: `OfflineDownloadsTests` verifica interruzione/ripresa, riapertura senza
rete, spazio insufficiente, integrità, isolamento account, cancellazione e
risposte tardive. `testOfflineDownloadRelaunchProgressAndRemoval` prova il ciclo
completo su iPhone e iPad: download, lettura esclusivamente da disco, riavvio,
progressi, scorrimento continuo e rimozione. Il manifest privacy dichiara il
controllo dello spazio disco (`E174.1`) per queste operazioni visibili all'utente.

## Connessione

In Connessione inserire URL locale e/o HTTPS, utente e password del lettore.
Automatico prova prima il locale, poi il remoto. Un aggiornamento della
libreria rivaluta gli indirizzi. I certificati TLS vengono sempre verificati;
HTTP è ammesso soltanto per host locali espliciti. I redirect sono rifiutati.
La password è salvata nel Portachiavi, accessibile solo a dispositivo sbloccato,
senza sincronizzazione iCloud. Gli altri dati di connessione sono in UserDefaults.

È possibile importare un JSON privato da File, quindi premere Connetti:

```json
{
  "localAddress": "https://reader.example.org",
  "remoteAddress": "https://reader.example.org",
  "username": "reader",
  "password": "REPLACE_ON_DEVICE"
}
```

Il file reale contiene una password: non versionarlo, non metterlo nel bundle
dell'app e cancellarlo da File dopo l'importazione. `instanceID` è facoltativo;
quando presente impedisce di accettare un server diverso da quello configurato.

## Build

Aprire `TankarrReader.xcodeproj` in Xcode. Il progetto è già versionato; per
rigenerarlo dopo aver aggiunto file Swift: `python3 generate_project.py`.

```sh
swift test
xcodebuild -project TankarrReader.xcodeproj -scheme 'Tankarr Reader' \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO build
```

Per un iPhone reale selezionare il proprio team in Signing & Capabilities e
il dispositivo abbinato a Xcode. La firma gratuita Personal Team richiede
periodicamente una nuova installazione; TestFlight richiede l'iscrizione
Apple Developer. Non sono necessari acquisti per compilare o provare sul
simulatore. L'app non include password, account Apple o certificati di firma.

## Pubblicazione

`AppStore/metadata.json` contiene i testi italiano/inglese; `REVIEW_NOTES.md`
le istruzioni per Apple; `SCREENSHOTS.md` la sequenza di acquisizione reale.
L'interfaccia è disponibile in italiano e inglese; la demo originale resta italiana.
`python3 Tools/check_store_assets.py` controlla limiti dei testi, icona e
manifest privacy incluso nel target. La schermata privacy è disponibile anche
offline; gli URL pubblici `/privacy` e `/support` servono documenti statici,
mentre libreria e API continuano a richiedere autenticazione.

Il client vive nel repository privato `Renzodef/tankarr-reader`, con progetto
Xcode, sorgenti e test alla radice. `Renzodef/tankarr` contiene il server;
`Renzodef/self-hosted` contiene il gateway e la configurazione dello stack.
Il workflow GitHub Actions
`Tankarr Reader iOS` usa un runner dedicato sul Mac personale ARM64: verifica
gli aggiornamenti del client su `main` e li invia al gruppo TestFlight interno.
Esegue i test del core, degli asset e dell'interfaccia su iPhone e iPad. Parte
solo dai push pertinenti su `main` o da un avvio manuale, senza trigger sulle
pull request. Un solo workflow alla volta può eseguire test e distribuzione;
un nuovo avvio non interrompe quello in corso.
L'azione manuale predefinita `verify` esegue tutti i test senza distribuzione;
`testflight` carica una nuova build dopo i test.

Il Mac deve essere acceso, sveglio e con la sessione utente disponibile. Se è
offline o in stop, i job restano in coda: non c'è un ripiego sui Mac ospitati
da GitHub e non vengono consumati i relativi minuti. Requisiti e verifica del
runner sono in [Tools/CI_RUNNER.md](Tools/CI_RUNNER.md).

L'invio alla revisione App Store è un'azione
manuale separata, con versione e build esplicite: non cambia una versione già
in revisione. Configurazione, comandi e rinnovo della firma sono descritti in
[BUILD_AND_UPLOAD.md](AppStore/BUILD_AND_UPLOAD.md).
