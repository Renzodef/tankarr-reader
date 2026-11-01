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
    /// Authentication, TLS, cancellation and server errors must remain visible;
    /// only loss of reachability is an automatic offline transition.
    public static func isReachabilityFailure(_ error: Error) -> Bool {
        guard let error = error as? URLError else { return false }
        return [.notConnectedToInternet, .networkConnectionLost, .timedOut,
                .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed].contains(error.code)
    }
}
