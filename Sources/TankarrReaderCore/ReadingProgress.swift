import Foundation

/// Positions are scoped to one server (or the independent offline demo).
public final class ReadingProgress {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    private func key(_ book: String, _ instance: String) -> String { "page.\(instance).\(book)" }
    public func storedPosition(book: String, instance: String) -> Int? {
        guard defaults.object(forKey: key(book, instance)) != nil else { return nil }
        return position(book: book, instance: instance)
    }
    public func position(book: String, instance: String) -> Int {
        max(0, defaults.integer(forKey: key(book, instance)))
    }
    public func save(_ page: Int, book: String, instance: String) {
        defaults.set(max(0, page), forKey: key(book, instance))
    }
    public func resumePosition(book: ReaderBook, instance: String, openingPage: Int? = nil, bookmark: ReaderBookmark? = nil) -> Int {
        let saved = openingPage ?? storedPosition(book: book.id, instance: instance) ??
            bookmark?.pageIndex ?? (book.bookmarked == true ? book.bookmarkPageIndex ?? book.pageIndex ?? 0 : 0)
        return min(max(0, saved), max(0, book.pageCount - 1))
    }
    public func clear() {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("page.") {
            defaults.removeObject(forKey: key)
        }
    }
}

/// Demo bookmarks stay on this device and never become server mutations.
public final class DemoBookmarkStore {
    private let defaults: UserDefaults
    private let key = "demo.bookmarks.v1"
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func all() -> [ReaderBookmark] {
        guard let data = defaults.data(forKey: key), let items = try? JSONDecoder().decode([ReaderBookmark].self, from: data) else { return [] }
        return items.sorted { $0.updatedAt > $1.updatedAt }
    }
    public func save(_ bookmark: ReaderBookmark) {
        var items = all().filter { $0.seriesId != bookmark.seriesId }
        items.append(bookmark)
        if let data = try? JSONEncoder().encode(items) { defaults.set(data, forKey: key) }
    }
    public func remove(series: String) {
        if let data = try? JSONEncoder().encode(all().filter { $0.seriesId != series }) { defaults.set(data, forKey: key) }
    }
    public func clear() { defaults.removeObject(forKey: key) }
}
