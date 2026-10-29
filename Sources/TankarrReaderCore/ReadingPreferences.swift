import Foundation

public enum ReaderDirection: String, Codable, CaseIterable, Identifiable {
    case automatic, ltr, rtl
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .automatic: return "Automatico"
        case .ltr: return "Sinistra → destra"
        case .rtl: return "Destra → sinistra"
        }
    }
}

public enum ReaderLayout: String, Codable, CaseIterable, Identifiable {
    case automatic, paged, continuous
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .automatic: return "Automatico"
        case .paged: return "A pagine"
        case .continuous: return "Scorrimento continuo"
        }
    }
}

public struct ReadingOptions: Codable, Equatable {
    public var direction: ReaderDirection
    public var layout: ReaderLayout

    public init(direction: ReaderDirection = .automatic, layout: ReaderLayout = .automatic) {
        self.direction = direction
        self.layout = layout
    }

    public func resolvedRTL(for book: ReaderBook) -> Bool {
        switch direction {
        case .automatic: return book.direction == "rtl"
        case .ltr: return false
        case .rtl: return true
        }
    }

    public func resolvedContinuous(for book: ReaderBook) -> Bool {
        switch layout {
        case .automatic: return book.mode == "webtoon"
        case .paged: return false
        case .continuous: return true
        }
    }
}

/// Reader choices belong to one book on one server, including the independent demo.
public final class ReadingPreferences {
    private let defaults: UserDefaults
    private let prefix = "reading.options.v1."

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private func key(_ book: String, _ instance: String) -> String {
        // Base64 components cannot contain the separator, avoiding ambiguous scopes.
        let server = Data(instance.utf8).base64EncodedString()
        let volume = Data(book.utf8).base64EncodedString()
        return "\(prefix)\(server).\(volume)"
    }

    public func options(book: String, instance: String) -> ReadingOptions {
        guard let data = defaults.data(forKey: key(book, instance)),
              let options = try? JSONDecoder().decode(ReadingOptions.self, from: data) else {
            return ReadingOptions()
        }
        return options
    }

    public func save(_ options: ReadingOptions, book: String, instance: String) {
        if let data = try? JSONEncoder().encode(options) {
            defaults.set(data, forKey: key(book, instance))
        }
    }

    public func clear() {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
    }
}
