import Foundation
import XCTest
@testable import TankarrReaderCore

final class AppLanguageTests: XCTestCase {
    func testEnglishInterfaceIsIndependentOfDeviceLanguage() {
        XCTAssertEqual(AppLanguage.allCases, [.english])
        for languages in [["it-IT", "en"], ["fr-FR", "it"], ["ja-JP"], []] {
            XCTAssertEqual(AppLanguage.english.code(preferredLanguages: languages), "en")
        }
    }

    func testPreferencePersistsAndInvalidValuesFallBackWithoutTouchingReadingData() {
        let suite = "AppLanguageTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("server profile", forKey: "serverProfile")
        defaults.set(3, forKey: "reading.position.example")
        let preferences = AppLanguagePreferences(defaults: defaults)
        XCTAssertEqual(preferences.language, .english)
        preferences.language = .english
        XCTAssertEqual(AppLanguagePreferences(defaults: defaults).language, .english)
        for old in ["italian", "system", "unsupported"] {
            defaults.set(old, forKey: AppLanguagePreferences.key)
            XCTAssertEqual(AppLanguagePreferences(defaults: defaults).language, .english)
            XCTAssertEqual(defaults.string(forKey: AppLanguagePreferences.key), "english")
        }
        XCTAssertEqual(defaults.string(forKey: "serverProfile"), "server profile")
        XCTAssertEqual(defaults.integer(forKey: "reading.position.example"), 3)
    }

    func testCatalogUsesEnglishAndPreservesUnknownBookContent() {
        XCTAssertEqual(L10n.text("Connessione", language: .english), "Connection")
        XCTAssertEqual(L10n.text("Segnalibri", language: .english, preferredLanguages: ["it-IT"]), "Bookmarks")
        XCTAssertEqual(L10n.text("Original book title", language: .english), "Original book title")
    }

    func testFormattingAndCoreErrorsAreEnglish() {
        let before = L10n.language
        defer { L10n.language = before }
        L10n.language = .english
        XCTAssertEqual(L10n.format("%@ · Pagina %d", "Volume 1", 7), "Volume 1 · Page 7")
        XCTAssertEqual(L10n.format("%d di %d", 2, 13), "2 of 13")
        XCTAssertEqual(ReaderError.unavailable(503).errorDescription, "Resource unavailable (503). Try again.")
        XCTAssertEqual(ConnectionMode.automatic.label, "Automatic")
    }

    func testTranslationsKeepFormatArgumentsInOrder() throws {
        let expression = try NSRegularExpression(pattern: "%[0-9$.*+\\-]*[a-zA-Z@]")
        func placeholders(_ string: String) -> [String] {
            expression.matches(in: string, range: NSRange(string.startIndex..., in: string)).map {
                String(string[Range($0.range, in: string)!])
            }
        }
        for (italian, english) in L10n.english {
            XCTAssertFalse(english.isEmpty, italian)
            XCTAssertEqual(placeholders(italian), placeholders(english), italian)
        }
    }

    func testInterfaceLiteralKeysHaveEnglishCoverage() throws {
        // Covers core labels, SwiftUI and UIKit. Dynamic metadata stays out of this
        // catalog. The iOS app and package share these sources, so check the originals.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let names = ["App/LibraryView.swift", "App/PrivacyView.swift", "App/TankarrReaderApp.swift",
                     "App/ReaderView.swift", "App/ContinuousReaderView.swift",
                     "App/DownloadsView.swift", "App/DownloadManager.swift", "App/SeriesDownloadRangeView.swift", "Sources/TankarrReaderCore/OfflineDownloads.swift",
                     "Sources/TankarrReaderCore/ReaderCore.swift", "Sources/TankarrReaderCore/ReadingPreferences.swift",
                     "Sources/TankarrReaderCore/ReaderNavigation.swift"]
        let expression = try NSRegularExpression(pattern: #"L10n\.(?:text|format)\("([^"\n]*)""#)
        for name in names {
            let contents = try String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)
            for match in expression.matches(in: contents, range: NSRange(contents.startIndex..., in: contents)) {
                let literal = String(contents[Range(match.range(at: 1), in: contents)!])
                let key = literal.replacingOccurrences(of: #"\n"#, with: "\n")
                XCTAssertNotNil(L10n.english[key], "Missing English translation: \(name): \(key)")
            }
        }
    }
}
