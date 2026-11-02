import Foundation

public enum ReaderDirection: String, Codable, CaseIterable, Identifiable {
    case automatic, ltr, rtl
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .automatic: return L10n.text("Automatico")
        case .ltr: return L10n.text("Sinistra → destra")
        case .rtl: return L10n.text("Destra → sinistra")
        }
    }
}

public enum ReaderLayout: String, Codable, CaseIterable, Identifiable {
    case automatic, paged, continuous
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .automatic: return L10n.text("Automatico")
        case .paged: return L10n.text("A pagine")
        case .continuous: return L10n.text("Scorrimento continuo")
        }
    }
}

public enum ReaderAxis: String, Codable, CaseIterable, Identifiable {
    case automatic, vertical, horizontal
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .automatic: return L10n.text("Automatico")
        case .vertical: return L10n.text("Verticale")
        case .horizontal: return L10n.text("Orizzontale")
        }
    }
}

public struct ReadingOptions: Codable, Equatable {
    public var direction: ReaderDirection
    public var layout: ReaderLayout
    public var axis: ReaderAxis

    public init(direction: ReaderDirection = .automatic, layout: ReaderLayout = .automatic,
                axis: ReaderAxis = .automatic) {
        self.direction = direction
        self.layout = layout
        self.axis = axis
    }

    private enum CodingKeys: String, CodingKey {
        case direction, layout, axis
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        direction = try values.decode(ReaderDirection.self, forKey: .direction)
        layout = try values.decode(ReaderLayout.self, forKey: .layout)
        // Build 5 saved only direction and layout. Preserve those choices when
        // opening existing preferences, retaining the old automatic axis.
        axis = try values.decodeIfPresent(ReaderAxis.self, forKey: .axis) ?? .automatic
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

    public func resolvedAxis(for book: ReaderBook) -> ReaderAxis {
        switch axis {
        case .automatic: return resolvedContinuous(for: book) ? .vertical : .horizontal
        case .vertical: return .vertical
        case .horizontal: return .horizontal
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

    public func snapshot(instance: String) -> [String: ReadingOptions] {
        let scope = prefix + Data(instance.utf8).base64EncodedString() + "."
        var result: [String: ReadingOptions] = [:]
        for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix(scope) {
            guard let raw = Data(base64Encoded: String(key.dropFirst(scope.count))),
                  let book = String(data: raw, encoding: .utf8), (try? Endpoint.identifier(book)) != nil,
                  let data = value as? Data,
                  let options = try? JSONDecoder().decode(ReadingOptions.self, from: data) else { continue }
            result[book] = options
        }
        return result
    }

    public func merge(_ options: [String: ReadingOptions], instance: String) throws {
        for book in options.keys { _ = try Endpoint.identifier(book) }
        for (book, value) in options { save(value, book: book, instance: instance) }
    }

    public func clear() {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
    }
}
