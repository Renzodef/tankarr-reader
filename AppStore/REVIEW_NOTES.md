# App Review — Tankarr Reader 1.0

Copy the English section into App Store Connect. No personal library credentials
belong in the repository or screenshots.

## Notes for the reviewer

Tankarr Reader browses a read-only library on a server supplied by the user and
can explicitly save or remove the server's reading bookmarks. It does
not supply a content subscription, an online discovery service, or downloads
from external sources. There are no purchases, advertising SDKs, or analytics.

On first launch, choose **“Esplora la libreria dimostrativa”** in the connection
screen. This built-in library works without an account or network connection
and uses the same library, book-list, page reader, zoom, progress and bookmark controls
as a connected server. All three short stories and vector illustrations were
created for this app. The demo does not expose the developer's private library.

1. Search for **“Segnali”** to exercise the library search.
2. Open **“Segnali dal faro”**, then **“Volume 1”**. Pinch or double-tap to zoom;
   use the arrows or page slider. Close and reopen to verify local progress.
   Use **“Segnalibro”** to save or remove a bookmark. The library's **“Segnalibri”**
   button lists saved pages and opens the selected page. Demo bookmarks stay
   on the device. On a connected server, one bookmark per series is shared with
   Tankarr and other readers/devices. Page turns only update local progress;
   saving a shared bookmark requires an explicit action.
3. **“Il giardino sospeso”** demonstrates right-to-left navigation.
4. **“Atlante delle nuvole”** demonstrates vertical pages and scrolling.
5. The network button opens **“Connessione”**. **“Privacy e assistenza”** contains
   the privacy policy, public support link, and a control to erase local reading
   positions and demo bookmarks. Server bookmarks are removed from the reader
   or bookmark list. **“Disconnetti”** removes saved server credentials and configuration.

Connecting a user-operated server requires its HTTPS endpoint, reader username,
and password; it uses HTTP Basic authentication over validated TLS. Local HTTP is
restricted to explicit local addresses. Administrative API routes and redirects
are not exposed. No Apple account, server account creation, or account purchase
is implemented inside this app. No sign-in is required for the included demo.

The interface and original demo stories are currently in Italian.

## Prima dell'invio

- Verificare attivazione del programma Developer, team e firma.
- Eseguire test su simulatore e iPhone reale; compilazione statica non basta.
- Acquisire screenshot reali dell'app con la demo: niente libreria privata o
  immagini dell'interfaccia inventate. Vedere `SCREENSHOTS.md`.
- Se Apple richiede un account del backend, predisporre un gateway separato
  con i soli contenuti demo; non fornire l'account personale del lettore.
- Rating: nessuna pubblicità/chat/browser/creazione di contenuti nell'app.
  Il catalogo collegato dipende dal server dell'utente: rispondere al questionario
  aggiornato in base alle opzioni effettivamente mostrate da App Store Connect.
- Privacy: il client non invia telemetria allo sviluppatore; il server scelto
  dall'utente e la diagnostica del sistema sono descritti nell'informativa.
- Cifratura: soltanto TLS e Portachiavi del sistema, nessun algoritmo o protocollo
  crittografico proprietario (`ITSAppUsesNonExemptEncryption = false`).

Riferimenti Apple verificati il 29 ottobre 2026:
- https://developer.apple.com/app-store/review/guidelines/
- https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots/
- https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype
