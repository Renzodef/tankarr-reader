# Configurazione portabile e aggiornamento

In **Connessione → Aggiorna Tankarr** si ricaricano catalogo, copertine,
segnalibri e serie seguite. Non avvia scansioni, download, riavvii o ricerche
sul server. Anche il gesto di aggiornamento della libreria usa questa via:
una sessione valida resta attiva, senza azzerare download o scritture pendenti.
Una richiesta annullata da iOS non diventa un errore di connessione. Soltanto
un reale cambio di raggiungibilità richiede di selezionare nuovamente LAN/HTTPS.
Il gesto in modalità offline aggiorna solo le copie sul dispositivo.

**Esporta configurazione…**, accanto a **Importa configurazione…**, salva un
JSON versione 1 nel percorso scelto tramite File. Contiene:

- indirizzi locale/HTTPS, utente, modalità di connessione e identità del server;
- lingua dell'interfaccia e opzioni di lettura dei singoli libri;
- elenco delle serie seguite per le notifiche.

Il file non contiene password, token APNs, file scaricati, coda download o
modifiche ai segnalibri non sincronizzate. Indirizzi, account e serie sono
comunque dati personali: condividerlo solo con chi deve riceverli.

Importare il file prepara i campi; toccare **Connetti** per verificarli e
applicare le preferenze. La password già salvata viene mantenuta solo per
lo stesso account/server; su un dispositivo nuovo si inserisce una volta.
Le vecchie configurazioni di sola connessione, anche quelle con password,
restano importabili; un nuovo export non copia mai quella password.

Le opzioni dei libri e le serie seguite si ripristinano solo dopo aver
verificato l'identità del server e lo stesso nome utente. Le serie seguite
si aggiungono a quelle già presenti, senza cancellare le altre. Il consenso
alle notifiche è di iOS e va dato sul singolo dispositivo: il JSON non può
trasferirlo, né può attivare APNs se il server non è configurato.
