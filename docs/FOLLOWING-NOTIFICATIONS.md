# Serie seguite e notifiche dei nuovi capitoli

Nella scheda di una serie, **Segui la serie** salva la scelta sul server per
l'account lettore. Toccare nuovamente **Serie seguita** interrompe gli avvisi.
La campanella nella libreria filtra le serie seguite; il filtro si combina con
ricerca e modalità offline. La scelta è condivisa tra i dispositivi dello
stesso account e distinta da segnalibri, monitoraggio e download automatici.
La demo conserva una selezione locale e non registra dispositivi con Apple.

Il primo Segui chiede il permesso iOS quando il server ha configurato le push.
Se viene negato, la serie resta seguita e la scheda offre **Apri impostazioni
notifiche**. iOS gestisce la consegna anche con Reader in background o chiuso;
non vengono creati polling, watcher o timer nell'app. Non si può ricevere una
push prima di aver installato una build compatibile, aperto l'app e consentito
le notifiche sul dispositivo.

Una notifica apre la scheda della serie. Il payload deve corrispondere a server
e account correnti; non può contenere comandi o URL da aprire. Il salvataggio
del segnalibro resta esplicito e non cambia per effetto di una notifica.

## Gateway e protocollo

Il gateway opt-in dell'self-hosted dichiara `following_writable` e
`push_notifications_available` in `GET /v1/status`. I vecchi server continuano
a funzionare senza questi campi. `GET /v1/follows` restituisce la selezione;
`PUT/DELETE /v1/series/ID/follow` la modifica; `PUT/DELETE
/v1/notifications/devices/UUID` registra o rimuove il solo dispositivo.
Le scritture richiedono autenticazione e `X-Tankarr-Reader: 1`, rifiutano Origin
browser e non consentono modifiche amministrative. Il proxy sovrascrive
`X-Tankarr-Reader-User` con l'account realmente autenticato.

Sul server, Tankarr invia l'evento `chapter_imported` al ricevitore interno,
protetto da un token dedicato. La serie viene fotografata al momento del Segui:
capitoli già presenti, backfill, sostituzioni e import duplicati non provocano
avvisi. Un capitolo è disponibile quando l'import in libreria è riuscito;
un annuncio online senza file leggibile non genera una push.

Il database conserva selezioni per account, dispositivi e un outbox persistente.
Gli errori temporanei di Apple vengono ritentati con backoff e limite; i token
revocati vengono rimossi. Nessun download o segnalibro viene cambiato. Il
backend non interroga periodicamente il catalogo: l'evento sveglia l'outbox.

Offline si può consultare la selezione salvata, ma per modificarla serve il
server. Tornare online ricarica le scelte. Disconnettere l'account rimuove la
registrazione push del dispositivo quando raggiungibile e disabilita la
registrazione locale presso APNs; gli altri dispositivi restano indipendenti.

## Configurazione Apple

Il bundle resta `app.tankarr.reader`. Abilitare **Push Notifications** per
l'App ID e rigenerare il profilo App Store con `aps-environment=production`.
La verifica della firma rifiuta profili privi di questa capability. Il progetto
usa l'ambiente sandbox in Debug e production in Release/TestFlight/App Store.

Il gateway richiede una chiave **APNs** `.p8`, il relativo Key ID e il Team ID.
Una chiave App Store Connect per pubblicare build non è una chiave APNs.
La chiave resta nel credential store del server, mai nell'app, in Git, nei
log o negli argomenti dei comandi. Senza configurazione il Segui funziona,
ma l'app dichiara esplicitamente che le push non sono ancora configurate.

Prima della distribuzione pubblica aggiornare la privacy: il server scelto
dal lettore riceve account, selezioni di serie, token APNs, lingua e ambiente
di notifica, esclusivamente per questa funzionalità. Non si usano tracciamento
o pubblicità. I file delle pagine e le password non entrano nelle notifiche.

## Verifica e rollback

I test core verificano compatibilità dei server precedenti, rotte ristrette e
isolamento delle notifiche tra account/server; il test UI prova Segui, filtro,
riapertura e rimozione su iPhone/iPad. I test del gateway verificano webhook
autenticato, baseline, deduplica, outbox persistente e rotazione dei token.
La consegna reale su iPhone richiede un token ottenuto da una build firmata e
permesso iOS concesso: una simulazione non attesta la consegna APNs.

Per disabilitare le push rimuovere la configurazione APNs del gateway e
riavviare soltanto il gateway. Per ritirare anche il Segui disabilitare la sua
configurazione, conservando il database per ripristino; i client vedranno la
capability disattivata. Segnalibri e libreria non dipendono da questo database.
