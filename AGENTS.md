# Tankarr Reader — sviluppo del client iOS

Repository pubblico dell'app SwiftUI per iPhone e iPad, iOS 17+.
Push diretto su `main`, senza force; niente branch/PR/issue senza richiesta.
Installare il controllo pre-push: `git config core.hooksPath .githooks`.
`./run-tests.sh` controlla tutta la suite Python e gli asset; `PYTHON` può
indicare l'interprete dell'ambiente virtuale. Non saltare gli hook.
Il bundle ID resta `app.tankarr.reader`: TestFlight e App Store usano lo stesso
record Apple esistente. Il server vive in `Renzodef/tankarr`; la configurazione
dello stack domestico vive in `Renzodef/self-hosted`.

## Ambiente e struttura

- Identificare la macchina con `hostname`, `uname -m` e, se presente,
  `/proc/device-tree/model` prima di attività operative.
- Le build e i test UI iOS richiedono macOS/Xcode. I test Python dei rilasci
  funzionano anche su Linux e non contattano Apple.
- `App/`: interfaccia SwiftUI e risorse; `Sources/`: core condiviso;
  `Tests/`: test Swift; `UITests/`: test UI; `tooling_tests/`: test Python dei rilasci.
- `generate_project.py` rigenera `TankarrReader.xcodeproj`; eseguirlo dopo
  l'aggiunta o rimozione di sorgenti o risorse gestiti dal generatore.
- Questo repository non contiene script di produzione del server. Non
  modificare o riavviare lo stack domestico per attività sul solo client.

## Verifica

Usare un ambiente Python con `pytest`, `requests` e `cryptography` installati.
Le versioni CI sono fissate in `.github/workflows/tankarr-ios.yml`.

```sh
python3 -m pytest tooling_tests/test_tankarr_ios_ci.py tooling_tests/test_tankarr_ios_release.py -q
python3 Tools/check_store_assets.py
```

Decisione di Renzo del 2 novembre 2026: per risparmiare spazio e velocizzare
TestFlight, la CI usa `python3 Tools/ci_build.py verify-device`: test del core,
asset e compilazione iOS senza runtime dei simulatori. Renzo prova la build
TestFlight sull'iPhone prima dell'invio pubblico; non dichiarare quei test
manuali eseguiti dall'agente. La compilazione non prova download in background,
push o navigazione su un dispositivo.

`python3 Tools/ci_build.py verify` resta disponibile per il percorso completo
con test UI iPhone/iPad nello stesso runtime iOS, anche tramite l'opzione
manuale `simulator_ui` del workflow. Non installare automaticamente runtime
pesanti. Le verifiche di firma e gli hook pre-push restano obbligatori.

## Credenziali e distribuzione

- Mai versionare connessioni private, password, chiavi `.p8`, certificati con
  chiavi private, profili di provisioning, keychain o configurazioni locali di
  firma. I dati demo devono restare originali e privi di informazioni personali.
- I Secrets Apple appartengono al repository GitHub e vengono iniettati solo
  nel passaggio di distribuzione, dopo i test e l'installazione delle dipendenze.
- I push pertinenti su `main` aggiornano il gruppo TestFlight interno.
  L'invio pubblico è solo tramite `workflow_dispatch` con azione `submit`,
  versione e build esplicite già provate. Non ritirare né sostituire una
  versione già in revisione per effetto di un push.
- Conservare la numerazione interrogando App Store Connect; non azzerarla
  dopo la separazione dal repository dello stack.
- Il P12 temporaneo d'importazione usa il formato compatibile macOS. L'UUID
  del profilo deve mantenere esattamente maiuscole e minuscole dell'originale.
- Durante la migrazione, disattivare il vecchio uploader e risolvere eventuali
  job pendenti prima del primo push con workflow attivo in questo repository.

Dettagli: [AppStore/BUILD_AND_UPLOAD.md](AppStore/BUILD_AND_UPLOAD.md).
