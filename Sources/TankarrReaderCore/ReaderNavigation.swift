import Foundation

/// Navigation follows the server's exact neighbours, never the filtered offline
/// list (which might otherwise silently skip an unavailable chapter).
public enum ReaderStep: Equatable {
    case page(Int)
    case chapter(String, lastPage: Bool)
    case unavailable(ReaderBoundary)
}

public enum ReaderBoundary: Equatable {
    case beginning, end, previousNotDownloaded, nextNotDownloaded
    public var message: String {
        switch self {
        case .beginning: return L10n.text("Non c’è un capitolo precedente.")
        case .end: return L10n.text("Non c’è un capitolo successivo.")
        case .previousNotDownloaded: return L10n.text("Il capitolo precedente non è scaricato. Torna online per leggerlo.")
        case .nextNotDownloaded: return L10n.text("Il capitolo successivo non è scaricato. Torna online per leggerlo.")
        }
    }
}

public enum ReaderNavigation {
    /// Reject a provable wrap in old downloaded metadata too. Never infer a
    /// neighbour from the filtered offline list: missing chapters still stop.
    public static func allowsTransition(from: ReaderBook, to: ReaderBook, forward: Bool,
                                        current: LibraryBook? = nil, candidate: LibraryBook? = nil) -> Bool {
        guard let a = position(title: current?.title ?? from.title, chapter: current?.chapter,
                               volume: current?.volume, unit: current?.unit),
              let b = position(title: candidate?.title ?? to.title, chapter: candidate?.chapter,
                               volume: candidate?.volume, unit: candidate?.unit), a.0 == b.0 else { return true }
        if a.1 != b.1 { return forward ? b.1 > a.1 : b.1 < a.1 }
        guard let first = a.2, let second = b.2 else { return true }
        return forward ? second > first : second < first
    }

    // Shared with list presentation so prologues and decimal chapters keep
    // the same meaning as the reader's boundary checks.
    static func position(title: String, chapter: String?, volume: String?, unit: String?) -> (String, Int, Double?)? {
        func number(_ text: String?) -> Double? {
            guard let text, let value = Double(text), value.isFinite else { return nil }; return value
        }
        func suffix(_ pattern: String) -> String? {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
                  match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: title) else { return nil }
            return String(title[range])
        }
        if title.range(of: "^prolog(?:ue|o)?\\b", options: [.regularExpression, .caseInsensitive]) != nil {
            return ("chapter", -1, number(suffix("^prolog(?:ue|o)?\\s+(\\d+(?:\\.\\d+)?)")))
        }
        if unit == "volume", let value = number(volume) { return ("volume", 0, value) }
        if let value = number(chapter) { return ("chapter", 0, value) }
        if let value = number(suffix("^(?:chapter|capitolo)\\s+(-?\\d+(?:\\.\\d+)?)")) { return ("chapter", 0, value) }
        return nil
    }

    public static func step(book: ReaderBook, page: Int, forward: Bool,
                            offline: Bool, downloaded: Set<String>) -> ReaderStep {
        let next = page + (forward ? 1 : -1)
        if (0..<book.pageCount).contains(next) { return .page(next) }
        guard let id = forward ? book.nextId : book.previousId,
              id != book.id, (try? Endpoint.identifier(id)) != nil else {
            return .unavailable(forward ? .end : .beginning)
        }
        if offline && !downloaded.contains(id) {
            return .unavailable(forward ? .nextNotDownloaded : .previousNotDownloaded)
        }
        return .chapter(id, lastPage: !forward)
    }
}

public enum OfflineConnectivity {
    /// Only loss of reachability is an automatic offline transition. Authentication,
    /// TLS and server errors remain visible; UI task cancellation is handled separately.
    public static func isReachabilityFailure(_ error: Error) -> Bool {
        guard let error = error as? URLError else { return false }
        return [.notConnectedToInternet, .networkConnectionLost, .timedOut,
                .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed].contains(error.code)
    }
}
