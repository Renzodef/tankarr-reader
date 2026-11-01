import Foundation

/// Use the catalog's reading order, not parsed chapter numbers: specials,
/// decimal chapters and volumes can all appear in the same series.
public enum DownloadSelection {
    public static func range(_ books: [LibraryBook], from first: String, through last: String) -> [LibraryBook] {
        guard let start = books.firstIndex(where: { $0.id == first }),
              let end = books.firstIndex(where: { $0.id == last }), start <= end else { return [] }
        return Array(books[start...end])
    }

    /// Include the bookmarked book. A missing/stale bookmark never downloads
    /// the entire series by accident.
    public static func fromBookmark(_ bookmark: ReaderBookmark?, seriesID: String,
                                    books: [LibraryBook]) -> [LibraryBook] {
        guard let bookmark, bookmark.seriesId == seriesID, let last = books.last else { return [] }
        return range(books, from: bookmark.bookId, through: last.id)
    }
}

public enum OfflineLibrary {
    public static func series(_ downloads: [OfflineDownload]) -> [LibrarySeries] {
        var seen = Set<String>()
        return downloads.filter { $0.complete && seen.insert($0.series.id).inserted }.map(\.series)
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    public static func books(seriesID: String, downloads: [OfflineDownload]) -> [LibraryBook] {
        downloads.filter { $0.complete && $0.series.id == seriesID }.map(\.listing)
            .sorted {
                let comparison = $0.label.localizedStandardCompare($1.label)
                return comparison == .orderedSame ? $0.id < $1.id : comparison == .orderedAscending
            }
    }

    /// A bookmark belongs to a downloaded series even when its own chapter is
    /// not downloaded. The UI explains that case and opens the series instead.
    public static func bookmarks(_ bookmarks: [ReaderBookmark], downloads: [OfflineDownload]) -> [ReaderBookmark] {
        let ids = Set(downloads.filter(\.complete).map { $0.series.id })
        return bookmarks.filter { ids.contains($0.seriesId) }
    }
}
