# App Review — Tankarr Reader 1.0

Copy the English section into App Store Connect. No personal library credentials
belong in the repository or screenshots.

## Notes for the reviewer

Tankarr Reader browses a read-only library on a server supplied by the user and
can explicitly save or remove the server's reading bookmarks. It does
not supply a content subscription, an online discovery service, or downloads
from external sources. There are no purchases, advertising SDKs, or analytics.

On first launch, choose **“Explore the demo library”** (Italian:
**“Esplora la libreria dimostrativa”**) in the connection screen. This built-in
library works without an account or network connection
and uses the same library, book-list, reading options, progress and bookmark controls
as a connected server. All three short stories and vector illustrations were
created for this app. The demo does not expose the developer's private library.

1. Search for **“Segnali”** to exercise the library search.
2. Open **“Segnali dal faro”**, then **“Volume 1”**. In paged mode, pinch or
   double-tap to zoom; use the arrows or page slider. Swipe to turn pages when
   not zoomed in; when zoomed in, dragging pans the current image. Close and
   reopen to verify local progress. Use **“Bookmark”** (**“Segnalibro”**) to save
   or remove a bookmark. The library's **“Bookmarks”** (**“Segnalibri”**)
   button lists saved pages and opens the selected page. Demo bookmarks stay
   on the device. On a connected server, one bookmark per series is shared with
   Tankarr and other readers/devices. Page turns only update local progress;
   saving a shared bookmark requires an explicit action.
3. **“Il giardino sospeso”** demonstrates right-to-left navigation. Open
   **“Reading options”** (**“Opzioni di lettura”**) to select an automatic,
   vertical or horizontal axis. With a horizontal axis, choose automatic,
   left-to-right or right-to-left direction. This direction applies to both
   paged and continuous reading. With a vertical axis, the horizontal direction
   selector is disabled; paged controls use up/down arrows and up/down swipes.
4. **“Atlante delle nuvole”** opens with continuous vertical scrolling. In
   **“Reading options”**, layout choices are automatic, paged and continuous.
   Automatic layout and direction follow the book's metadata; automatic axis
   means vertical for continuous layout and horizontal for paged layout.
   Try continuous mode with both axes, including right-to-left horizontal
   scrolling. Images load as needed, and distant images are released to limit
   memory use. The visible loaded page supplies local progress and the page
   offered by the bookmark menu; bookmarks still require an explicit save.
   Zoom is available in paged mode. Direction, layout and axis choices are saved
   locally for each volume and server, separately from the demo. Change a setting,
   close the volume and reopen it to verify persistence. Switching layout or axis
   keeps the current page; existing preferences from build 5 retain their direction
   and layout with an automatic axis.
5. The network button opens **“Connection”** (**“Connessione”**). Under
   **“App language”** (**“Lingua dell'app”**), choose **“System”**, **“Italiano”**,
   or **“English”**. System is the default: it selects the first supported language
   (Italian or English) from iOS language preferences, falling back to English.
   Changes apply immediately without resetting the connected server or reading
   position. The setting translates the interface, not books or demo content.
6. **“Privacy and support”** (**“Privacy e assistenza”**) contains
   the privacy policy, public support link, and a control to erase local reading
   positions, per-volume reading preferences and demo bookmarks. Server bookmarks are removed from the reader
   or bookmark list. **“Disconnect”** (**“Disconnetti”**) removes saved server
   credentials and configuration.

Connecting a user-operated server requires its HTTPS endpoint, reader username,
and password; it uses HTTP Basic authentication over validated TLS. Local HTTP is
restricted to explicit local addresses. Administrative API routes and redirects
are not exposed. No Apple account, server account creation, or account purchase
is implemented inside this app. No sign-in is required for the included demo.

The interface is available in Italian and English. The original demo stories
and their titles remain in Italian.

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
