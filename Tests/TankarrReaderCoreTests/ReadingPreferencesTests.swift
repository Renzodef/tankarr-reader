import XCTest
@testable import TankarrReaderCore

final class ReadingPreferencesTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suite = "app.tankarr.reader.preferences.tests." + UUID().uuidString
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    override func tearDownWithError() throws {
        defaults?.removePersistentDomain(forName: suite)
        defaults = nil
        suite = nil
        try super.tearDownWithError()
    }

    private func book(direction: String, mode: String) -> ReaderBook {
        ReaderBook(id: "book", seriesTitle: "Series", title: "Volume", pageCount: 8,
                   direction: direction, mode: mode, previousId: nil, nextId: nil)
    }

    func testNewBookUsesAutomaticOptions() {
        let options = ReadingPreferences(defaults: defaults).options(book: "book", instance: "server")
        XCTAssertEqual(options.direction, .automatic)
        XCTAssertEqual(options.layout, .automatic)
        XCTAssertEqual(options.axis, .automatic)
        XCTAssertFalse(options.resolvedRTL(for: book(direction: "unknown", mode: "unknown")))
        XCTAssertFalse(options.resolvedContinuous(for: book(direction: "unknown", mode: "unknown")))
        XCTAssertEqual(options.resolvedAxis(for: book(direction: "unknown", mode: "unknown")), .horizontal)
    }

    func testAutomaticOptionsFollowLatestBookMetadata() {
        let preferences = ReadingPreferences(defaults: defaults)
        preferences.save(ReadingOptions(), book: "book", instance: "server")
        let options = preferences.options(book: "book", instance: "server")
        let manga = book(direction: "rtl", mode: "manga")
        XCTAssertTrue(options.resolvedRTL(for: manga))
        XCTAssertFalse(options.resolvedContinuous(for: manga))
        let updated = book(direction: "ltr", mode: "webtoon")
        XCTAssertFalse(options.resolvedRTL(for: updated))
        XCTAssertTrue(options.resolvedContinuous(for: updated))
    }

    func testManualDirectionAndLayoutOverrideBookMetadata() {
        let leftToRightPages = ReadingOptions(direction: .ltr, layout: .paged)
        let rtlWebtoon = book(direction: "rtl", mode: "webtoon")
        XCTAssertFalse(leftToRightPages.resolvedRTL(for: rtlWebtoon))
        XCTAssertFalse(leftToRightPages.resolvedContinuous(for: rtlWebtoon))

        let rightToLeftScroll = ReadingOptions(direction: .rtl, layout: .continuous)
        let ltrManga = book(direction: "ltr", mode: "manga")
        XCTAssertTrue(rightToLeftScroll.resolvedRTL(for: ltrManga))
        XCTAssertTrue(rightToLeftScroll.resolvedContinuous(for: ltrManga))
    }

    func testDirectionAndLayoutCanRemainAutomaticIndependently() {
        let rtlWebtoon = book(direction: "rtl", mode: "webtoon")
        let manualDirection = ReadingOptions(direction: .ltr)
        XCTAssertFalse(manualDirection.resolvedRTL(for: rtlWebtoon))
        XCTAssertTrue(manualDirection.resolvedContinuous(for: rtlWebtoon))
        let manualLayout = ReadingOptions(layout: .paged)
        XCTAssertTrue(manualLayout.resolvedRTL(for: rtlWebtoon))
        XCTAssertFalse(manualLayout.resolvedContinuous(for: rtlWebtoon))
    }

    func testAutomaticAxisUsesResolvedLayout() {
        let manga = book(direction: "rtl", mode: "manga")
        let webtoon = book(direction: "ltr", mode: "webtoon")
        XCTAssertEqual(ReadingOptions().resolvedAxis(for: manga), .horizontal)
        XCTAssertEqual(ReadingOptions().resolvedAxis(for: webtoon), .vertical)
        XCTAssertEqual(ReadingOptions(layout: .continuous).resolvedAxis(for: manga), .vertical)
        XCTAssertEqual(ReadingOptions(layout: .paged).resolvedAxis(for: webtoon), .horizontal)
    }

    func testAxisIsIndependentFromDirectionAndLayout() {
        for direction in ReaderDirection.allCases {
            for layout in ReaderLayout.allCases {
                for mode in ["manga", "webtoon"] {
                    let volume = book(direction: "rtl", mode: mode)
                    for axis in [ReaderAxis.vertical, .horizontal] {
                        let options = ReadingOptions(direction: direction, layout: layout, axis: axis)
                        let original = ReadingOptions(direction: direction, layout: layout)
                        XCTAssertEqual(options.resolvedAxis(for: volume), axis)
                        XCTAssertEqual(options.resolvedRTL(for: volume), original.resolvedRTL(for: volume))
                        XCTAssertEqual(options.resolvedContinuous(for: volume), original.resolvedContinuous(for: volume))
                    }
                }
            }
        }
    }

    func testBuildFivePreferencesPreserveChoicesWhenAxisIsMissing() throws {
        let preferences = ReadingPreferences(defaults: defaults)
        let previousKeys = Set(defaults.dictionaryRepresentation().keys)
        preferences.save(ReadingOptions(), book: "book", instance: "server")
        let key = try XCTUnwrap(Set(defaults.dictionaryRepresentation().keys).subtracting(previousKeys).first)
        defaults.set(Data(#"{"direction":"rtl","layout":"continuous"}"#.utf8), forKey: key)

        let migrated = preferences.options(book: "book", instance: "server")
        XCTAssertEqual(migrated, ReadingOptions(direction: .rtl, layout: .continuous, axis: .automatic))
        XCTAssertEqual(migrated.resolvedAxis(for: book(direction: "ltr", mode: "manga")), .vertical)
        preferences.save(migrated, book: "book", instance: "server")
        XCTAssertEqual(preferences.options(book: "book", instance: "server"), migrated)
    }

    func testPreferencesSurviveReopeningAndSeparateBooksServersAndDemo() throws {
        let preferences = ReadingPreferences(defaults: defaults)
        let first = ReadingOptions(direction: .rtl, layout: .paged, axis: .vertical)
        let second = ReadingOptions(direction: .ltr, layout: .continuous, axis: .horizontal)
        let otherBook = ReadingOptions(layout: .continuous)
        let demo = ReadingOptions(direction: .ltr)
        preferences.save(first, book: "book", instance: "server-a")
        preferences.save(second, book: "book", instance: "server-b")
        preferences.save(otherBook, book: "other-book", instance: "server-a")
        preferences.save(demo, book: "book", instance: DemoCatalog.instanceID)

        let reopenedDefaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let reopened = ReadingPreferences(defaults: reopenedDefaults)
        XCTAssertEqual(reopened.options(book: "book", instance: "server-a"), first)
        XCTAssertEqual(reopened.options(book: "book", instance: "server-b"), second)
        XCTAssertEqual(reopened.options(book: "other-book", instance: "server-a"), otherBook)
        XCTAssertEqual(reopened.options(book: "book", instance: DemoCatalog.instanceID), demo)
        XCTAssertEqual(reopened.options(book: "other-book", instance: "server-b"), ReadingOptions())
        XCTAssertEqual(reopened.options(book: "book", instance: "server-c"), ReadingOptions())

        reopened.save(ReadingOptions(), book: "book", instance: "server-a")
        XCTAssertEqual(preferences.options(book: "book", instance: "server-a"), ReadingOptions())
        XCTAssertEqual(preferences.options(book: "book", instance: "server-b"), second)
    }

    func testInstanceAndBookNamesCannotCollide() {
        let preferences = ReadingPreferences(defaults: defaults)
        let first = ReadingOptions(direction: .rtl)
        let second = ReadingOptions(layout: .continuous)
        preferences.save(first, book: "chapter", instance: "server.book")
        preferences.save(second, book: "book.chapter", instance: "server")
        XCTAssertEqual(preferences.options(book: "chapter", instance: "server.book"), first)
        XCTAssertEqual(preferences.options(book: "book.chapter", instance: "server"), second)
    }

    func testCorruptOrUnsupportedStoredOptionsFallBackToAutomatic() throws {
        let preferences = ReadingPreferences(defaults: defaults)
        let previousKeys = Set(defaults.dictionaryRepresentation().keys)
        preferences.save(ReadingOptions(direction: .rtl, layout: .continuous), book: "book", instance: "server")
        let key = try XCTUnwrap(Set(defaults.dictionaryRepresentation().keys).subtracting(previousKeys).first)
        for corrupt in ["not json", "{}", "{\"direction\":\"rtl\",\"layout\":\"unsupported\"}",
                        #"{"direction":"rtl","layout":"continuous","axis":"unsupported"}"#,
                        #"{"direction":"rtl","layout":"continuous","axis":42}"#] {
            defaults.set(Data(corrupt.utf8), forKey: key)
            XCTAssertEqual(preferences.options(book: "book", instance: "server"), ReadingOptions())
        }
        defaults.set(42, forKey: key)
        XCTAssertEqual(preferences.options(book: "book", instance: "server"), ReadingOptions())
    }

    func testClearOnlyRemovesReadingPreferences() {
        let preferences = ReadingPreferences(defaults: defaults)
        let progress = ReadingProgress(defaults: defaults)
        let bookmarks = DemoBookmarkStore(defaults: defaults)
        let bookmark = ReaderBookmark(seriesId: "series", seriesTitle: "Series", bookId: "book", label: "Volume",
                                      pageIndex: 2, updatedAt: "2026-10-29T12:00:00Z")
        preferences.save(ReadingOptions(direction: .rtl), book: "book", instance: "server")
        preferences.save(ReadingOptions(layout: .continuous), book: "book", instance: DemoCatalog.instanceID)
        progress.save(5, book: "book", instance: "server")
        progress.save(3, book: "book", instance: DemoCatalog.instanceID)
        bookmarks.save(bookmark)
        defaults.set("profile fixture", forKey: "serverProfile")
        defaults.set(true, forKey: "demoMode")

        preferences.clear()

        XCTAssertEqual(preferences.options(book: "book", instance: "server"), ReadingOptions())
        XCTAssertEqual(preferences.options(book: "book", instance: DemoCatalog.instanceID), ReadingOptions())
        XCTAssertEqual(progress.position(book: "book", instance: "server"), 5)
        XCTAssertEqual(progress.position(book: "book", instance: DemoCatalog.instanceID), 3)
        XCTAssertEqual(bookmarks.all(), [bookmark])
        XCTAssertEqual(defaults.string(forKey: "serverProfile"), "profile fixture")
        XCTAssertTrue(defaults.bool(forKey: "demoMode"))
    }
}
