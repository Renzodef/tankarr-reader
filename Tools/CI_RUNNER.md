# Runner Mac di Tankarr Reader

Il workflow `Tankarr Reader iOS` usa il Mac personale Apple Silicon con queste
etichette: `self-hosted`, `macOS`, `ARM64`, `tankarr-reader`. Il runner è
registrato soltanto nel repository privato `Renzodef/tankarr-reader`.

## Requisiti e registrazione

- Xcode installato in `/Applications/Xcode.app`, primo avvio completato e
  SDK iOS disponibile. Per il flusso normale non serve un runtime dei simulatori.
  Un runtime con iPhone e iPad serve solo per i test UI opzionali.
- Python 3 di Homebrew in `/opt/homebrew/bin/python3` e accesso di rete a GitHub
  e ai servizi Apple. Il workflow usa esplicitamente questo interprete per
  preparare le dipendenze in un ambiente virtuale temporaneo.
- Utente del Mac con sessione aperta, Mac sveglio e connessione disponibile
  per tutta la durata di test e distribuzione. Il servizio del runner deve
  operare nella sessione di questo utente, necessaria ai simulatori.

La registrazione si gestisce in GitHub → repository → **Settings → Actions →
Runners → New self-hosted runner**, scegliendo macOS e ARM64 e aggiungendo
l'etichetta `tankarr-reader`. La directory prevista sul Mac è
`~/Developer/actions-runner-tankarr-reader`. Usare le istruzioni e il token
temporaneo mostrati da GitHub per registrare il runner e configurare il suo
servizio; token e file locali di configurazione restano fuori dal repository.
Verificare nella pagina Runners che tutte le etichette siano presenti e lo
stato sia **Idle** prima di avviare un workflow.

## Esecuzione e coda

Il workflow parte solo dai push pertinenti su `main` e da `workflow_dispatch`;
non esegue codice delle pull request. Tutti i job richiedono le quattro
etichette indicate sopra. La concorrenza è impostata sull'intero workflow con
`cancel-in-progress: false`: un solo flusso di test e distribuzione alla volta,
senza interrompere quello in corso. GitHub può sostituire un'esecuzione ancora
in attesa con una più recente dello stesso gruppo di concorrenza.

I controlli comprendono le protezioni Python del rilascio, `swift test`, gli
asset App Store e la compilazione iOS per dispositivo generico senza firma.
Dal 2 novembre 2026 Renzo verifica l'interfaccia sull'iPhone reale con TestFlight;
questa verifica manuale non viene dichiarata eseguita dalla CI. Dopo i controlli, i push su `main`
distribuiscono automaticamente al gruppo TestFlight interno. L'azione manuale
predefinita `verify` esegue questi controlli e salta la distribuzione; `testflight`
carica una nuova build dopo i test. `submit` richiede versione e build esplicite
già provate e mantiene i controlli che impediscono di modificare una versione
già in revisione. Avviare `verify` da `main` per collaudare il runner senza
caricare un'altra build su Apple. Selezionare `simulator_ui` solo per aggiungere
i test UI iPhone/iPad con un runtime già installato; la CI non scarica runtime.

Se il Mac è spento, offline o in stop, il job resta in coda finché il runner
torna disponibile, nei limiti della coda GitHub. Non è configurato un runner
ospitato di riserva e non vengono consumati minuti dei Mac ospitati da GitHub.

## Verifica dalla radice del repository

Con un ambiente virtuale attivo creato da `/opt/homebrew/bin/python3` e le
dipendenze Python indicate nel workflow installate:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
./run-tests.sh
python3 Tools/ci_build.py verify-device
```

`verify-device` rigenera il progetto ed esegue core, asset e compilazione iOS
senza simulatori. La lettura, i download in background, i segnalibri e le push
vanno poi provati sulla build TestFlight dell'iPhone prima dell'invio pubblico.

`verify` resta il comando opzionale per core, asset e test UI sulle due famiglie
di simulatori. I risultati UI sono in `build/results/`; la verifica non
richiede credenziali Apple. I simulatori già avviati restano accesi; quelli
avviati dalla CI vengono spenti al termine. La CI non cancella i simulatori.
I test UI avviano l'app con `--demo` e modificano solo progressi e segnalibri
della demo, senza richieste al server personale.

## Firma e pulizia

I Secrets Apple sono gli stessi descritti in
[BUILD_AND_UPLOAD.md](../AppStore/BUILD_AND_UPLOAD.md) e vengono forniti solo
al passaggio di distribuzione, dopo l'installazione delle dipendenze e i test.
La firma usa un keychain temporaneo, P12, chiave `.p8` e profilo con permessi
restrittivi. Il cleanup elimina il materiale creato dalla CI anche in caso di
errore e ripristina la configurazione dei keychain.

Un profilo di provisioning già presente e identico viene riutilizzato senza
modificarlo o rimuoverlo. Un profilo diverso nello stesso percorso fa fallire
la distribuzione: la CI non sovrascrive i profili personali del Mac.
