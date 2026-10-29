# Screenshot reali per lo store

Le acquisizioni del 29 ottobre 2026 sono in `screenshots/iphone-6.9/` e
`screenshots/ipad-13/`: quattro PNG originali per dispositivo, esportati dai
test UI passati su iPhone 18 Pro Max e iPad Pro 13" (M5). Mostrano soltanto
la demo inclusa e sono stati controllati visivamente, senza ritocchi.

Usare la demo inclusa. L'icona originale è in `App/Assets.xcassets`:
1024 × 1024, opaca. Non usare screenshot con account, indirizzi del server
privato, notifiche di altre app o librerie personali.

Per ciascun dispositivo acquisire:

1. **Libreria** — le tre copertine originali, ricerca e dicitura Demo.
2. **Volumi** — “Segnali dal faro”, elenco libri.
3. **Lettore** — prima pagina del racconto, controlli di navigazione visibili.
4. **Webtoon** — “Atlante delle nuvole”, pagina verticale.

Formati scelti dalla tabella Apple: iPhone 1320 × 2868 (verticale), iPad
2064 × 2752 (verticale). PNG RGB senza alpha. Se il runtime installato offre un
altro dispositivo, scegliere una risoluzione ammessa dalla tabella Apple;
non deformare l'interfaccia per raggiungere le dimensioni richieste.

Il target `TankarrReaderUITests` verifica ricerca, lettura e ripresa della pagina
e allega quattro screenshot reali al risultato XCTest. Eseguirlo su iPhone Pro
Max e iPad Pro 13", poi esportare gli allegati con `xcresulttool` e ispezionarli:

```sh
xcodebuild -project TankarrReader.xcodeproj -scheme 'Tankarr Reader' \
  -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
  -resultBundlePath build/ReaderUI.xcresult CODE_SIGNING_ALLOWED=NO test
xcrun xcresulttool export attachments --path build/ReaderUI.xcresult \
  --output-path build/screenshots
```

Da un simulatore già configurato e avviato:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun simctl status_bar "$SIMULATOR_UDID" override --time '9:41' \
  --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
xcrun simctl launch "$SIMULATOR_UDID" app.tankarr.reader --demo
# Navigare nella schermata prevista, poi:
xcrun simctl io "$SIMULATOR_UDID" screenshot --type=png --mask=ignored library.png
# Al termine:
xcrun simctl status_bar "$SIMULATOR_UDID" clear
```

Controllare visivamente le immagini prima dell'invio. Il progetto può essere
compilato senza firma per il simulatore; la prima configurazione di Xcode deve
comunque essere completata.

https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications
