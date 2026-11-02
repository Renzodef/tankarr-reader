import Foundation

public enum ReaderListSort: String, CaseIterable, Identifiable, Sendable {
    case recent, seriesTitle
    public var id: String { rawValue }
    public var title: String { L10n.text(self == .recent ? "Recenti" : "Serie A–Z") }
}

public struct DownloadSeriesGroup: Identifiable, Sendable {
    public let series: LibrarySeries
    public let items: [OfflineDownload]
    public let latestAt: Date
    public var id: String { series.id }
}

/// Presentation order only: never changes download scheduling or saved bookmarks.
public enum ReaderListOrdering {
    private static func titleBefore(_ lhs: String, _ rhs: String, lhsID: String, rhsID: String) -> Bool {
        let result = lhs.localizedStandardCompare(rhs)
        return result == .orderedSame ? lhsID < rhsID : result == .orderedAscending
    }

    public static func bookmarks(_ values: [ReaderBookmark], sort: ReaderListSort) -> [ReaderBookmark] {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        return values.map { value in
            (value, fractional.date(from: value.updatedAt) ?? plain.date(from: value.updatedAt) ?? .distantPast)
        }.sorted { lhs, rhs in
            if sort == .recent, lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            return titleBefore(lhs.0.seriesTitle, rhs.0.seriesTitle, lhsID: lhs.0.id, rhsID: rhs.0.id)
        }.map(\.0)
    }

    public static func downloadGroups(_ values: [OfflineDownload], sort: ReaderListSort) -> [DownloadSeriesGroup] {
        Dictionary(grouping: values, by: { $0.series.id }).values.map { items in
            let latest = items.max { lhs, rhs in
                lhs.createdAt == rhs.createdAt ? lhs.id < rhs.id : lhs.createdAt < rhs.createdAt
            }!
            return DownloadSeriesGroup(series: latest.series, items: items.sorted(by: bookBefore), latestAt: latest.createdAt)
        }.sorted { lhs, rhs in
            if sort == .recent, lhs.latestAt != rhs.latestAt { return lhs.latestAt > rhs.latestAt }
            return titleBefore(lhs.series.title, rhs.series.title, lhsID: lhs.id, rhsID: rhs.id)
        }
    }

    private static func bookBefore(_ lhs: OfflineDownload, _ rhs: OfflineDownload) -> Bool {
        func position(_ value: LibraryBook) -> (kind: Int, number: Double) {
            guard let p = ReaderNavigation.position(title: value.title, chapter: value.chapter,
                                                    volume: value.volume, unit: value.unit) else { return (3, .infinity) }
            let kind = p.0 == "chapter" ? (p.1 < 0 ? 0 : 1) : 2
            return (kind, p.2 ?? .infinity)
        }
        let a = position(lhs.listing), b = position(rhs.listing)
        if a.kind != b.kind { return a.kind < b.kind }
        if a.number != b.number { return a.number < b.number }
        return titleBefore(lhs.listing.label, rhs.listing.label, lhsID: lhs.id, rhsID: rhs.id)
    }
}
