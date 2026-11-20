import Foundation

/// Interface language is independent of the server and the books' content.
public enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case system, italian, english
    public static let supportedCodes = ["en", "it"]
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .system: return L10n.text("Sistema")
        case .italian: return "Italiano"
        case .english: return "English"
        }
    }
    public func code(preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        switch self {
        case .italian: return "it"
        case .english: return "en"
        case .system:
            for language in preferredLanguages {
                let base = language.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init)
                if let base, Self.supportedCodes.contains(base) { return base }
            }
            return "en"
        }
    }
}

public final class AppLanguagePreferences {
    private let defaults: UserDefaults
    public static let key = "app.language.v2"
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public var language: AppLanguage {
        get {
            if let raw = defaults.string(forKey: Self.key) {
                return AppLanguage(rawValue: raw) ?? .system
            }
            // 1.0.1 wrote "english" even when the user never chose it. Start
            // following iOS again; retain an older Italian/System preference.
            let legacy = defaults.string(forKey: "app.language.v1")
            let initial: AppLanguage = legacy == "italian" ? .italian : .system
            defaults.set(initial.rawValue, forKey: Self.key)
            return initial
        }
        set { defaults.set(newValue.rawValue, forKey: Self.key) }
    }
}

/// A shared catalog also serves UIKit accessibility and core errors. No Bundle.module
/// dependency: the same core files compile both as a Swift package and inside the iOS app.
public enum L10n {
    private static let lock = NSLock()
    private static var selectedLanguage = AppLanguage.system
    public static var language: AppLanguage {
        get { lock.lock(); defer { lock.unlock() }; return selectedLanguage }
        set { lock.lock(); defer { lock.unlock() }; selectedLanguage = newValue }
    }
    public static var locale: Locale { Locale(identifier: language.code()) }

    public static func text(_ italianKey: String) -> String {
        text(italianKey, language: language)
    }
    public static func text(_ italianKey: String, language: AppLanguage,
                            preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        language.code(preferredLanguages: preferredLanguages) == "it" ? italianKey : english[italianKey] ?? italianKey
    }
    public static func format(_ italianFormat: String, _ arguments: CVarArg...) -> String {
        let selected = language
        return String(format: text(italianFormat, language: selected), locale: Locale(identifier: selected.code()), arguments: arguments)
    }

    // Keys are the original Italian UI copy. Library metadata, artwork and story text
    // never pass through this catalog: changing the UI does not translate a book.
    static let english: [String: String] = [
        "Cataloghi collegati": "Linked catalogues",
        "Riprova i download": "Retry downloads",
        "Ricollegamento…": "Reconnecting…",
        "Attiva modalità offline": "Enable offline mode",
        "Mostra solo i libri scaricati e mette in pausa i download finché non torni online.": "Show downloaded books only and pause downloads until you go back online.",
        "Serie seguite non disponibili offline": "Followed series are unavailable offline",
        "Torna online per vedere le serie seguite e gestire le notifiche.": "Go online to see followed series and manage notifications.",
        "Aggiorna Tankarr": "Refresh Tankarr",
        "Tankarr aggiornato": "Tankarr refreshed",
        "Esporta configurazione…": "Export configuration…",
        "Impossibile ripristinare tutte le serie seguite. Reimporta la configurazione per riprovare.": "Unable to restore all followed series. Import the configuration again to retry.",
        "L’esportazione contiene indirizzi, utente, lingua, opzioni di lettura e serie seguite. Non contiene password, download o token push. Dopo l’importazione tocca Connetti: le serie seguite vengono aggiunte solo allo stesso account e server; il consenso alle notifiche va dato su ogni dispositivo.": "The export contains addresses, username, language, reading options and followed series. It contains no passwords, downloads or push tokens. After importing, tap Connect: followed series are added only to the same account and server; notification permission must be granted on each device.",
        "Se segui una serie e consenti le notifiche, il server salva la selezione e riceve il token APNs del dispositivo, lingua e account per avvisarti dei nuovi capitoli. Apple consegna l’avviso, che contiene titolo e numero del capitolo. Puoi smettere di seguire una serie o disabilitare le notifiche nelle impostazioni iOS.": "If you follow a series and allow notifications, your server stores the selection and receives the device APNs token, language and account to notify you about new chapters. Apple delivers the alert, which includes the chapter title and number. You can unfollow a series or disable notifications in iOS Settings.",
        "Serie seguite": "Followed series",
        "Tutti gli stati": "All statuses",
        "In corso": "Ongoing",
        "Concluse": "Completed",
        "In pausa": "On hiatus",
        "Interrotte": "Cancelled",
        "Stato sconosciuto": "Unknown status",
        "Stato della serie": "Series status",
        "Nessuna serie con questo stato": "No series with this status",
        "Scegli un altro stato o mostra tutte le serie.": "Pick another status or show every series.",
        "Mostra tutte": "Show all",
        "Ordina per": "Sort by",
        "Recenti": "Recent",
        "Serie A–Z": "Series A–Z",
        "Nessuna serie seguita": "No followed series",
        "Apri una serie e tocca Segui per ricevere gli avvisi dei nuovi capitoli.": "Open a series and tap Follow to receive new chapter alerts.",
        "Serie seguita": "Following series",
        "Segui la serie": "Follow series",
        "Ricevi un avviso quando un nuovo capitolo è disponibile nella tua libreria.": "Get notified when a new chapter is available in your library.",
        "Le notifiche push non sono ancora configurate su questo server.": "Push notifications are not configured on this server yet.",
        "Apri impostazioni notifiche": "Open notification settings",
        "Attiva notifiche": "Enable notifications",
        "Impossibile aggiornare le serie seguite. Riprova.": "Unable to refresh followed series. Try again.",
        "Impossibile modificare le serie seguite. Riprova.": "Unable to change followed series. Try again.",
        "Impossibile attivare le notifiche. Riprova dalle impostazioni.": "Unable to enable notifications. Try again in Settings.",
        "Registrazione notifiche in attesa. Riprova tornando online.": "Notification registration is pending. Try again when online.",
        "Non c’è un capitolo precedente.": "There is no previous chapter.",
        "Non c’è un capitolo successivo.": "There is no next chapter.",
        "Il capitolo precedente non è scaricato. Torna online per leggerlo.": "The previous chapter is not downloaded. Go online to read it.",
        "Il capitolo successivo non è scaricato. Torna online per leggerlo.": "The next chapter is not downloaded. Go online to read it.",
        "Salva o sposta il segnalibro alla pagina aperta.": "Save or move the bookmark to the open page.",
        "Apro il capitolo…": "Opening chapter…",
        "Navigazione capitoli": "Chapter navigation",
        "OK": "OK",
        "Riprendi dal segnalibro": "Resume from bookmark",
        "Apri un capitolo e tocca l’icona Segnalibro in alto, poi Salva segnalibro.": "Open a chapter, tap the Bookmark icon at the top, then Save bookmark.",
        "Segnalibro non disponibile offline": "Bookmark unavailable offline",
        "Il capitolo del segnalibro non è scaricato. Torna online per leggerlo.": "The bookmarked chapter is not downloaded. Go online to read it.",
        "Torna online": "Go online",
        "Offline automatico": "Automatically offline",
        "Il pulsante con il Wi-Fi barrato mostra solo i download. Se manca la rete, l’app passa automaticamente alle copie scaricate e riprova al ritorno della rete o alla riapertura. Se attivi Offline tu, resta attivo finché tocchi Torna online.": "The crossed-out Wi-Fi button shows downloads only. If the network is unavailable, the app switches to downloaded copies and retries when the network returns or the app reopens. If you turn Offline on yourself, it stays on until you tap Go online.",
        "Una copia dei segnalibri, le modifiche in attesa di sincronizzazione e le copertine dei download restano nell’archivio privato, separate per server e account. Le modifiche ai segnalibri vengono inviate quando torni online; fino alla conferma del server restano sul dispositivo.": "Cached bookmarks, pending changes and download covers stay in private storage, separated by server and account. Bookmark changes are sent when you go back online and stay on this device until the server confirms them.",
        "Disconnetti elimina il profilo, la password, i download e le modifiche ai segnalibri non sincronizzate dell’account corrente. Rimuovere soltanto i download conserva le modifiche pendenti. I progressi di lettura locali si cancellano separatamente. Per rimuovere un segnalibro condiviso usa l’elenco Segnalibri o il menu del lettore.": "Disconnect removes the current account’s profile, password, downloads and unsynced bookmark changes. Removing only downloads keeps pending changes. Local reading progress is cleared separately. To remove a shared bookmark, use the Bookmarks list or the reader menu.",
        "Modalità offline": "Offline mode",
        "Annulla": "Cancel",
        "Attiva": "On",
        "Disattiva": "Off",
        "%d file scaricati": "%d downloaded files",
        "Disattiva Offline per scegliere i libri da scaricare.": "Turn Offline off to choose books to download.",
        "Segnalibri delle serie scaricate. Le modifiche restano sul dispositivo e si sincronizzano quando torni online.": "Bookmarks for downloaded series. Changes stay on this device and sync when you go back online.",
        "%d modifiche in attesa di sincronizzazione": "%d changes waiting to sync",
        "Modifica salvata sul dispositivo, in attesa di sincronizzazione": "Change saved on this device, waiting to sync",
        "Modifiche salvate sul dispositivo. Sincronizzazione non riuscita: %@": "Changes saved on this device. Sync failed: %@",
        "Impossibile salvare il segnalibro sul dispositivo. %@": "Unable to save the bookmark on this device. %@",
        "Le modifiche ai segnalibri non ancora sincronizzate saranno eliminate dal dispositivo. I segnalibri sul server restano invariati.": "Unsynced bookmark changes will be removed from this device. Server bookmarks remain unchanged.",
        "Il capitolo del segnalibro non è scaricato. Apri la serie per leggere le copie disponibili.": "The bookmarked chapter is not downloaded. Open the series to read the available copies.",
        "Impossibile salvare i segnalibri per l’uso offline. %@": "Unable to save bookmarks for offline use. %@",
        "Impossibile leggere i segnalibri offline. %@": "Unable to read offline bookmarks. %@",
        "Torna alla serie": "Back to series",
        "Download della serie": "Series downloads",
        "Scarica intervallo…": "Download range…",
        "Scarica intervallo": "Download range",
        "Scarica dal segnalibro alla fine": "Download from bookmark to end",
        "Rimuovi download della serie": "Remove series downloads",
        "Rimuovere tutti i download di questa serie?": "Remove all downloads for this series?",
        "Da": "From",
        "A": "Through",
        "Entrambi gli estremi sono inclusi. I libri già scaricati vengono saltati; quelli incompleti riprendono dalle pagine mancanti.": "Both endpoints are included. Downloaded books are skipped; incomplete books resume from their missing pages.",
        "Scarica %d libri": "Download %d books",
        "Puoi cambiare app: i download continuano in background e la coda resta salvata.": "You can switch apps: downloads continue in the background and the queue stays saved.",
        "Riprendi la coda": "Resume queue",
        "Una copia dei segnalibri e le copertine dei download sono salvate nello stesso archivio privato per consultarli offline. La copia dei segnalibri si aggiorna quando ti colleghi al server.": "A copy of bookmarks and downloaded covers is saved in the same private storage for offline access. The bookmark copy refreshes when you connect to the server.",
        "Download": "Downloads",
        "Lettura offline": "Offline reading",
        "Scarica tutti": "Download all",
        "Pausa download": "Pause download",
        "Riprendi download": "Resume download",
        "Avanzamento download": "Download progress",
        "In coda · posizione %d": "Queued · position %d",
        "%d libri scaricati · %d in coda": "%d books downloaded · %d queued",
        "Scaricato · Rimuovi dal dispositivo": "Downloaded · Remove from device",
        "Scarica sul dispositivo": "Download to device",
        "Rimuovere questa copia dal dispositivo?": "Remove this copy from your device?",
        "Rimuovi download": "Remove download",
        "La libreria e i segnalibri sul server restano invariati.": "Your server library and bookmarks stay unchanged.",
        "Spazio usato: %@": "Storage used: %@",
        "I download continuano quando cambi app o blocchi lo schermo. La coda viene salvata: dopo una chiusura forzata riprende alla riapertura dalle pagine mancanti. iOS decide i tempi in background.": "Downloads continue when you switch apps or lock the screen. The queue is saved: after a force-quit it resumes on reopening from missing pages. iOS controls background timing.",
        "%d download in coda": "%d queued downloads",
        "Ricollega al server": "Reconnect to server",
        "Usa senza connessione": "Use offline",
        "Nessun download": "No downloads",
        "Apri una serie e tocca la freccia accanto al capitolo o volume.": "Open a series and tap the arrow next to a chapter or volume.",
        "Disponibile offline": "Available offline",
        "%d di %d pagine scaricate": "%d of %d pages downloaded",
        "In pausa · Riprendi per completare": "Paused · Resume to finish",
        "Download interrotto": "Download interrupted",
        "Spazio sul dispositivo": "Storage on this device",
        "Totale sul dispositivo": "Total on this device",
        "Dati della libreria": "Library data",
        "Copertine": "Covers",
        "Volumi scaricati": "Downloaded books",
        "Gestisci download": "Manage downloads",
        "Elimina %@": "Delete %@",
        "Liberare spazio sul dispositivo?": "Free up space on this device?",
        "Aggiorna catalogo e tutte le copertine": "Refresh library and all covers",
        "Dati salvati aggiornati": "Saved library updated",
        "%d copertine non aggiornate": "%d covers could not be refreshed",
        "%d di %d copertine controllate": "%d of %d covers checked",
        "Interrompi": "Stop",
        "Rimuovi tutti i download": "Remove all downloads",
        "Rimuovere tutti i download di questo account?": "Remove all downloads for this account?",
        "Disconnettere ed eliminare i download di questo account?": "Disconnect and delete downloads for this account?",
        "Questo libro non è scaricato sul dispositivo.": "This book has not been downloaded to your device.",
        "Download incompleto o danneggiato. Ricollegati e riprendi il download.": "Incomplete or damaged download. Reconnect and resume the download.",
        "Spazio insufficiente. Libera spazio sul dispositivo e riprova.": "Not enough storage. Free up space on your device and try again.",
        "Pagina non valida o troppo grande per il download.": "Invalid page or page too large to download.",
        "Il libro sul server è cambiato. Rimuovi la copia locale e scaricalo di nuovo.": "The book on the server has changed. Remove the local copy and download it again.",
        "Il download è stato annullato.": "The download was cancelled.",
        "Impossibile aprire l’archivio dei download sul dispositivo.": "Unable to open the on-device download storage.",
        "I download scelti da te restano nell’archivio privato dell’app, protetti dal dispositivo ed esclusi dal backup iCloud. Sono separati per server e account. Puoi rimuoverli da Download senza cancellare nulla sul server.": "Downloads you choose stay in the app’s private storage, protected by your device and excluded from iCloud backup. They are separated by server and account. Remove them from Downloads without deleting anything on the server.",
        "Disconnetti elimina il profilo, la password e i download dell’account corrente. I progressi di lettura locali si cancellano separatamente. Per rimuovere un segnalibro dal server usa l’elenco Segnalibri o il menu del lettore quando sei connesso.": "Disconnect removes the profile, password and current account’s downloads. Local reading progress can be cleared separately. To remove a server bookmark, use the Bookmarks list or reader menu while connected.",
        "Sistema": "System",
        "Lingua dell’app": "App language",
        "La lingua dell’interfaccia è salvata su questo dispositivo. Sistema segue la lingua preferita dell’iPhone o iPad fra italiano e inglese; le altre lingue usano l’inglese. Non cambia la lingua dei libri.": "The interface language is saved on this device. System follows your iPhone or iPad’s preferred language among Italian and English; other languages use English. It does not change the language of your books.",
        "Non connesso": "Not connected",
        "Connesso": "Connected",
        "Demo sul dispositivo": "On-device demo",
        "Connessione non riuscita": "Connection failed",
        "Riprova": "Try again",
        "Apro la libreria…": "Opening the library…",
        "La tua libreria, con te": "Your library, with you",
        "Collega il lettore al tuo server Tankarr.": "Connect the reader to your Tankarr server.",
        "Configura connessione": "Set up connection",
        "Esplora la demo": "Explore the demo",
        "%d file disponibili": "%d files available",
        "Cerca per titolo o autore": "Search by title or author",
        "Cancella ricerca": "Clear search",
        "Autori": "Authors",
        "Nessuna serie di questo autore": "No series by this author",
        "Segnalibri": "Bookmarks",
        "Connessione": "Connection",
        "Libreria in sola lettura": "Read-only library",
        "I segnalibri della demo restano su questo dispositivo.": "Demo bookmarks stay on this device.",
        "Un segnalibro per serie, condiviso con Tankarr e gli altri dispositivi. Salvalo dal lettore per scegliere dove riprendere.": "One bookmark per series, shared with Tankarr and your other devices. Save it in the reader to choose where to resume.",
        "Aggiorna segnalibri": "Refresh bookmarks",
        "Carico i segnalibri…": "Loading bookmarks…",
        "Nessun segnalibro": "No bookmarks",
        "Apri un libro e usa Segnalibro per salvare una pagina.": "Open a book and use Bookmark to save a page.",
        "%@ · Pagina %d": "%@ · Page %d",
        "Riprendi lettura": "Resume reading",
        "Rimuovi": "Remove",
        "Aggiorno i segnalibri…": "Updating bookmarks…",
        "Chiudi": "Close",
        "Carico i libri…": "Loading books…",
        "Disponibili da leggere": "Available to read",
        "Esplora la libreria dimostrativa": "Explore the demo library",
        "Tre racconti originali per provare ricerca, lettura e zoom. Funziona senza account e senza connessione.": "Three original stories to try search, reading and zoom. No account or connection required.",
        "Server": "Server",
        "Indirizzo locale (opzionale)": "Local address (optional)",
        "Indirizzo HTTPS": "HTTPS address",
        "Account lettore": "Reader account",
        "Utente": "Username",
        "Password": "Password",
        "Connetti": "Connect",
        "Importa configurazione…": "Import configuration…",
        "La password resta nel Portachiavi. L’ultima pagina letta è ricordata su questo dispositivo; i segnalibri salvati dal lettore sono condivisi con Tankarr. In Automatico provo prima l’indirizzo locale e poi HTTPS; aggiorna la libreria per cambiare rete.": "Your password stays in Keychain. The last page read is remembered on this device; bookmarks saved in the reader are shared with Tankarr. Automatic tries the local address first, then HTTPS; refresh the library to switch networks.",
        "Privacy e assistenza": "Privacy and support",
        "Disconnetti": "Disconnect",
        "Configurazione non valida: %@": "Invalid configuration: %@",
        "Impossibile aggiornare i segnalibri. %@": "Unable to refresh bookmarks. %@",
        "Segnalibro non confermato. Aggiorna l’elenco per verificarlo. %@": "Bookmark not confirmed. Refresh the list to check it. %@",
        "Rimozione non confermata. Aggiorna l’elenco per verificarla. %@": "Removal not confirmed. Refresh the list to check it. %@",
        "Sul tuo dispositivo": "On your device",
        "La password del lettore è custodita nel Portachiavi e non viene sincronizzata con iCloud. Indirizzi del server, nome utente, preferenze, ultima pagina letta e segnalibri della demo restano nei dati dell’app; possono essere inclusi nei backup del dispositivo.": "Your reader password is kept in Keychain and is not synced with iCloud. Server addresses, username, preferences, last page read and demo bookmarks remain in app data and may be included in device backups.",
        "Copertine e pagine vengono caricate in memoria. L’app non scarica interi libri per la lettura offline.": "Covers and pages are loaded into memory. The app does not download entire books for offline reading.",
        "Quando ti colleghi": "When you connect",
        "L’app invia credenziali e richieste di lettura soltanto al server che configuri. Il suo gestore può vedere l’indirizzo IP e le risorse richieste secondo le proprie regole di conservazione. HTTPS verifica il certificato; HTTP è disponibile soltanto sulla rete locale.": "The app sends credentials and reading requests only to the server you configure. Its operator can see your IP address and requested resources under their own retention rules. HTTPS verifies the certificate; HTTP is available only on the local network.",
        "Quando salvi, sposti o rimuovi un segnalibro, l’app aggiorna il segnalibro della serie sul tuo server Tankarr. Ogni serie ha un solo segnalibro, condiviso con gli altri lettori e dispositivi del server. Il cambio pagina aggiorna soltanto la posizione locale: usa Segnalibro per scegliere la pagina condivisa.": "When you save, move or remove a bookmark, the app updates that series’ bookmark on your Tankarr server. Each series has one bookmark, shared with the server’s other readers and devices. Turning pages updates only your local position: use Bookmark to choose the shared page.",
        "Nessun tracciamento": "No tracking",
        "Nessuna pubblicità, SDK di analisi o profilazione. La libreria dimostrativa funziona sul dispositivo, senza account e senza richieste di rete.": "No advertising, analytics SDKs or profiling. The demo library runs on your device, without an account or network requests.",
        "Gestisci i dati": "Manage data",
        "Disconnetti, nella schermata Connessione, elimina il profilo e la password salvata. Puoi cancellare le posizioni locali, le preferenze di lettura dei volumi e i segnalibri della demo. Per rimuovere un segnalibro dal server usa l’elenco Segnalibri o il menu del lettore.": "Disconnect on the Connection screen removes the saved profile and password. You can clear local positions, book reading preferences and demo bookmarks. To remove a server bookmark, use the Bookmarks list or the reader menu.",
        "Cancella dati di lettura locali": "Clear local reading data",
        "Dati di lettura locali cancellati.": "Local reading data cleared.",
        "Informazioni e assistenza": "Information and support",
        "Informativa privacy sul web": "Privacy policy online",
        "Assistenza Tankarr Reader": "Tankarr Reader support",
        "Cancellare posizioni locali, preferenze di lettura e segnalibri della demo?": "Clear local positions, reading preferences and demo bookmarks?",
        "Cancella dati locali": "Clear local data",
        "I segnalibri condivisi restano sul server Tankarr.": "Shared bookmarks remain on your Tankarr server.",
        "Usa un indirizzo HTTPS valido. HTTP è consentito solo per indirizzi della rete locale.": "Use a valid HTTPS address. HTTP is allowed only for local network addresses.",
        "Identificativo della risorsa non valido.": "Invalid resource identifier.",
        "Inserisci utente e password dell’account lettore.": "Enter your reader account username and password.",
        "Utente o password del lettore non validi.": "Invalid reader username or password.",
        "Questo indirizzo non è il lettore Tankarr configurato.": "This address is not your configured Tankarr reader.",
        "Risorsa non disponibile (%d). Riprova.": "Resource unavailable (%d). Try again.",
        "Automatico": "Automatic",
        "Locale": "Local",
        "Remoto": "Remote",
        "Sinistra → destra": "Left → right",
        "Destra → sinistra": "Right → left",
        "A pagine": "Paged",
        "Scorrimento continuo": "Continuous scrolling",
        "Verticale": "Vertical",
        "Orizzontale": "Horizontal",
        "Asse di lettura": "Reading axis",
        "Verso orizzontale": "Horizontal direction",
        "Lettura dall’alto in basso": "Reading from top to bottom",
        "In verticale si legge dall’alto in basso. Il verso sinistra/destra si applica solo all’asse orizzontale.": "Vertical reading goes from top to bottom. Left/right direction applies only to the horizontal axis.",
        "L’asse automatico è verticale nel continuo e orizzontale a pagine. Modalità e verso automatici seguono il volume. Le scelte restano salvate su questo dispositivo per volume, senza modificare i segnalibri.": "Automatic axis is vertical in continuous mode and horizontal in paged mode. Automatic mode and direction follow the book. Your choices stay saved on this device per book, without changing bookmarks.",
        "Chiudi libro": "Close book",
        "Caricamento…": "Loading…",
        "Salva segnalibro": "Save bookmark",
        "Sposta segnalibro a questa pagina": "Move bookmark to this page",
        "Rimuovi segnalibro": "Remove bookmark",
        "Segnalibro": "Bookmark",
        "Lettura da destra a sinistra": "Reading right to left",
        "Lettura da sinistra a destra": "Reading left to right",
        "Opzioni di lettura": "Reading options",
        "Salvo il segnalibro…": "Saving bookmark…",
        "Segnalibro a pagina %d": "Bookmark on page %d",
        "Pagina successiva": "Next page",
        "Pagina precedente": "Previous page",
        "Pagina": "Page",
        "%d di %d": "%d of %d",
        "Verso di lettura": "Reading direction",
        "Selezionato": "Selected",
        "Visualizzazione": "Display",
        "Automatico segue le indicazioni del volume. Le tue scelte restano salvate su questo dispositivo per questo volume, senza modificare i segnalibri.": "Automatic follows the book’s metadata. Your choices are saved on this device for this book, without changing bookmarks.",
        "Lettura": "Reading",
        "Fine": "Done",
        "Pagina del libro": "Book page",
        "Immagine non valida.": "Invalid image.",
        "Pagina %d del libro": "Book page %d",
        "Riprova pagina %d": "Retry page %d",
        "Impossibile caricare pagina %d.\n%@": "Unable to load page %d.\n%@"
    ]
}
