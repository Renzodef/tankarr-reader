import Foundation

/// Original, bundled examples. This catalog never contacts a server.
public enum DemoCatalog {
    public static let instanceID = "tankarr-reader-demo-v1"
    public static let series: [LibrarySeries] = [
        LibrarySeries(id: "demo-lighthouse", title: "Segnali dal faro",
            description: "Una luce nella nebbia, un messaggio da decifrare. Racconto originale della libreria dimostrativa.",
            authors: ["Tankarr Reader · Demo"], language: "it", booksCount: 1, coverPath: ""),
        LibrarySeries(id: "demo-garden", title: "Il giardino sospeso",
            description: "Tre piccoli passi per far tornare verde una città. Racconto originale, da sfogliare da destra a sinistra.",
            authors: ["Tankarr Reader · Demo"], language: "it", booksCount: 1, coverPath: ""),
        LibrarySeries(id: "demo-clouds", title: "Atlante delle nuvole",
            description: "Un viaggio verticale tra vento, colori e nuove prospettive. Esempio originale in formato webtoon.",
            authors: ["Tankarr Reader · Demo"], language: "it", booksCount: 1, coverPath: "")
    ]

    private static let narratives: [[String]] = [
        ["Quando il porto scomparve nella nebbia, Ada rimase ad ascoltare. Dal faro arrivavano tre lampi, poi una pausa.",
         "Non era un allarme. Sul vetro della lanterna qualcuno aveva disegnato una mappa: il sentiero era sempre stato lì.",
         "All'alba Ada raggiunse la piccola isola. Accese la sua luce e aspettò. Dalla costa, finalmente, qualcuno rispose."],
        ["Sul tetto più alto, Neri trovò un vaso vuoto. La città era grigia, ma una foglia era arrivata fin lassù.",
         "Un vicino portò la terra, un'altra vicina l'acqua. Ogni sera il tetto cambiava colore, poco alla volta.",
         "Quando il primo fiore si aprì, nessuno ricordava più chi avesse cominciato. Il giardino era diventato di tutti."],
        ["Mira disegnava nuvole sul suo taccuino. Ogni forma sembrava immobile, finché alzava di nuovo gli occhi.",
         "Seguì una corrente d'aria oltre la collina. Le nuvole non indicavano una destinazione: mostravano possibilità.",
         "L'ultima pagina dell'atlante rimase bianca. Mira sorrise: il cielo di domani non era ancora stato disegnato."]
    ]

    public struct Page {
        public let seriesID: String
        public let title: String
        public let narration: String
        public let index: Int
        public let count: Int
        public let vertical: Bool
    }

    public static func books(for seriesID: String) throws -> [LibraryBook] {
        guard let item = series.first(where: { $0.id == seriesID }) else { throw ReaderError.invalidIdentifier }
        return [LibraryBook(id: item.id + "-volume-1", label: "Volume 1", title: "Un nuovo inizio",
            volume: "1", chapter: "", unit: "volume", language: "it")]
    }

    private static func index(for bookID: String) throws -> Int {
        guard let index = series.firstIndex(where: { $0.id + "-volume-1" == bookID }) else { throw ReaderError.invalidIdentifier }
        return index
    }

    public static func book(_ bookID: String) throws -> ReaderBook {
        let index = try index(for: bookID)
        return ReaderBook(id: bookID, seriesTitle: series[index].title, title: "Volume 1 · Un nuovo inizio",
            pageCount: narratives[index].count, direction: index == 1 ? "rtl" : "ltr",
            mode: index == 2 ? "webtoon" : "manga", previousId: nil, nextId: nil, seriesId: series[index].id)
    }

    public static func page(_ bookID: String, at page: Int) throws -> Page {
        let index = try index(for: bookID)
        guard narratives[index].indices.contains(page) else { throw ReaderError.invalidIdentifier }
        return Page(seriesID: series[index].id, title: series[index].title,
            narration: narratives[index][page], index: page, count: narratives[index].count, vertical: index == 2)
    }
}
