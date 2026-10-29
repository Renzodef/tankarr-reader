import Foundation

/// Interface language is a device preference, independent of the server and book language.
public enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case system, italian, english
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
                if base == "it" || base == "en" { return base! }
            }
            return "en"
        }
    }
}

public final class AppLanguagePreferences {
    private let defaults: UserDefaults
    public static let key = "app.language.v1"
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public var language: AppLanguage {
        get { defaults.string(forKey: Self.key).flatMap(AppLanguage.init(rawValue:)) ?? .system }
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
        "Cerca nella libreria": "Search your library",
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
