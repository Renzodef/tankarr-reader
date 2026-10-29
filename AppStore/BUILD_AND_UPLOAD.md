# Compilazione, TestFlight e App Store

Il workflow [Tankarr Reader iOS](../.github/workflows/tankarr-ios.yml)
compila il codice alla radice del repository `Renzodef/tankarr-reader` sul Mac
personale ARM64, con Xcode in `/Applications/Xcode.app`. Il runner dedicato al
repository usa le etichette `self-hosted`, `macOS`, `ARM64`, `tankarr-reader`.
Il repository contiene sorgenti e metadati; le credenziali Apple sono nei
repository Secrets di GitHub. Requisiti, disponibilità del Mac e registrazione
sono descritti in [Tools/CI_RUNNER.md](../Tools/CI_RUNNER.md).

## Flusso automatico

1. Un push pertinente su `main` esegue i test Python del rilascio, `swift test`,
   il controllo dei materiali App Store e i test UI su un iPhone e un iPad
   disponibili nel simulatore. Questi passaggi non ricevono credenziali Apple.
   Il workflow non ha trigger sulle pull request.
2. Dopo il superamento dei test, crea un archivio firmato, esporta l'IPA e la
   carica in App Store Connect.
3. Il workflow attende l'elaborazione Apple e aggiunge la build al gruppo
   TestFlight **interno** configurato. I tester ricevono gli aggiornamenti da
   TestFlight; sul dispositivo possono attivare gli aggiornamenti automatici.

La versione automatica viene da `AppStore/metadata.json`, campo `version`.
Il numero di build viene calcolato interrogando App Store Connect. La concorrenza
è globale al workflow: un solo flusso di test e distribuzione alla volta, con
`cancel-in-progress: false`. GitHub può sostituire un'esecuzione ancora in
attesa con un push più recente. Se il Mac è offline o in stop, i job restano
in coda senza usare runner macOS ospitati né consumarne i minuti.
`MARKETING_VERSION` e `CURRENT_PROJECT_VERSION` vengono passati a `xcodebuild`.

Un push non seleziona build per App Review, non modifica i metadati pubblici e
non ritira una versione già in revisione.

## Avvio manuale

In GitHub → Actions → **Tankarr Reader iOS** → **Run workflow**, selezionare
sempre il ramo `main`:

| Azione | Versione | Build | Risultato |
| --- | --- | --- | --- |
| `verify` (predefinita) | Non usata | Non usata | Esegue tutti i test, senza firmare, caricare o distribuire una build |
| `testflight` | Facoltativa; altrimenti dal file dei metadati | Facoltativa; altrimenti prossimo numero Apple | Compila, firma, carica e distribuisce al gruppo interno |
| `submit` | Obbligatoria, nel formato `X.Y.Z` | Obbligatoria, già presente e provata in TestFlight | Seleziona quella build e invia la versione pubblica ad App Review |

`submit` riutilizza la build esistente: non ricompila e non carica una nuova
IPA. Prima di avviarlo, preparare la versione pubblica in App Store Connect,
completare screenshot, localizzazioni, note di revisione, privacy, rating,
diritti sui contenuti e gli eventuali adempimenti richiesti dall'account.
Il controllo del workflow rifiuta versioni già in revisione e build non
idonee. Non crea versioni pubbliche e non compila dichiarazioni al posto del
titolare. L'approvazione e la disponibilità sull'App Store dipendono da Apple
e dalle impostazioni di rilascio della versione.

Per il prossimo numero di versione aggiornare `AppStore/metadata.json` e
`generate_project.py`, quindi rigenerare il progetto. Apple consente di creare
una nuova versione pubblica quando quella corrente è pronta per la distribuzione.
Una build TestFlight può essere poi usata per il rilascio pubblico: l'esportazione
CI non applica la limitazione «TestFlight Internal Only».

## Configurazione GitHub

Repository Secrets:

| Nome | Contenuto |
| --- | --- |
| `TANKARR_ASC_PRIVATE_KEY` | Testo PEM completo della chiave API App Store Connect `.p8` |
| `TANKARR_DISTRIBUTION_P12_BASE64` | Certificato Apple Distribution con chiave privata, P12 in base64 senza interruzioni |
| `TANKARR_DISTRIBUTION_P12_PASSWORD` | Password del P12 |
| `TANKARR_PROFILE_BASE64` | Profilo App Store per `app.tankarr.reader`, in base64 senza interruzioni |

Repository Variables:

| Nome | Contenuto |
| --- | --- |
| `TANKARR_ASC_KEY_ID` | ID della chiave API |
| `TANKARR_ASC_ISSUER_ID` | Issuer ID della chiave API di team |
| `TANKARR_ASC_APP_ID` | ID numerico di Tankarr Reader in App Store Connect |
| `TANKARR_ASC_BETA_GROUP_ID` | ID del gruppo TestFlight interno già configurato |
| `TANKARR_TEAM_ID` | Team ID dell'Apple Developer Program |

Il gruppo interno e i relativi tester devono esistere in App Store Connect.
La chiave API deve poter caricare build e gestire l'app; il ruolo App Manager
è sufficiente. Certificato e profilo vanno rinnovati prima della scadenza e
sostituiti nei Secrets. Il workflow controlla team, bundle ID, validità e
corrispondenza fra certificato e profilo prima della firma.

Le dipendenze Python vengono installate prima di introdurre i segreti.
La distribuzione usa un keychain temporaneo e file con permessi restrittivi;
il cleanup rimuove keychain, P12, `.p8` e profili creati dalla CI anche dopo un
errore e ripristina la configurazione dei keychain. Un profilo già presente e
identico viene riutilizzato senza modificarlo né rimuoverlo; un profilo diverso
nello stesso percorso blocca la distribuzione. Solo il passaggio di
distribuzione su `main` riceve i Secrets. Le credenziali non sono negli argomenti
dei test, negli artefatti o nel repository.

## Verifica sul Mac

Dopo il primo avvio di Xcode e l'installazione dei runtime iOS, dalla radice
del repository e con l'ambiente Python descritto nella
[guida del runner](../Tools/CI_RUNNER.md) attivo:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
python3 Tools/ci_build.py verify
```

Il comando rigenera il progetto ed esegue gli stessi test dell'app del runner.
Richiede un simulatore iPhone e un iPad disponibili nello stesso runtime iOS.
I risultati UI restano in `build/results/`; nessun account Apple è necessario.
I simulatori già accesi restano avviati; quelli avviati dalla CI vengono spenti
al termine, senza cancellarne i dati.

Riferimenti: [firma su GitHub Actions](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications),
[caricamento build Apple](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds),
[tester interni](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers).
