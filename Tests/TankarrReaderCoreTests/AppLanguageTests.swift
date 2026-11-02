import Foundation
import XCTest
@testable import TankarrReaderCore

final class AppLanguageTests: XCTestCase {
    func testSystemUsesFirstSupportedPreferredLanguageAndEnglishFallback() {
        XCTAssertEqual(AppLanguage.allCases, [.system, .italian, .english])
        XCTAssertEqual(AppLanguage.system.code(preferredLanguages: ["it-IT", "en-US"]), "it")
        XCTAssertEqual(AppLanguage.system.code(preferredLanguages: ["en-GB", "it-IT"]), "en")
        XCTAssertEqual(AppLanguage.system.code(preferredLanguages: ["fr-FR", "IT_ch"]), "it")
        XCTAssertEqual(AppLanguage.system.code(preferredLanguages: ["ja-JP"]), "en")
        XCTAssertEqual(AppLanguage.system.code(preferredLanguages: []), "en")
        for languages in [["it-IT", "en"], ["fr-FR", "it"], ["ja-JP"], []] {
            XCTAssertEqual(AppLanguage.english.code(preferredLanguages: languages), "en")
            XCTAssertEqual(AppLanguage.italian.code(preferredLanguages: languages), "it")
        }
    }

    func testPreferencePersistsAndInvalidValuesFallBackWithoutTouchingReadingData() {
        let suite = "AppLanguageTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("server profile", forKey: "serverProfile")
        defaults.set(3, forKey: "reading.position.example")
        let preferences = AppLanguagePreferences(defaults: defaults)
        XCTAssertEqual(preferences.language, .system)
        for language in AppLanguage.allCases {
            preferences.language = language
            XCTAssertEqual(AppLanguagePreferences(defaults: defaults).language, language)
        }
        defaults.set("unsupported", forKey: AppLanguagePreferences.key)
        XCTAssertEqual(preferences.language, .system)
        XCTAssertEqual(defaults.string(forKey: "serverProfile"), "server profile")
        XCTAssertEqual(defaults.integer(forKey: "reading.position.example"), 3)
    }

    func testEnglishOnlyUpgradeUsesSystemOnceAndKeepsLaterExplicitChoice() {
        let suite = "AppLanguageMigration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppLanguagePreferences(defaults: defaults)
        let cases: [(String, AppLanguage)] = [("english", .system), ("italian", .italian), ("system", .system)]
        for (legacy, expected) in cases {
            defaults.removeObject(forKey: AppLanguagePreferences.key)
            defaults.set(legacy, forKey: "app.language.v1")
            XCTAssertEqual(preferences.language, expected)
            preferences.language = .english
            XCTAssertEqual(AppLanguagePreferences(defaults: defaults).language, .english)
        }
    }

    func testCatalogUsesSelectedLanguageAndPreservesUnknownBookContent() {
        XCTAssertEqual(L10n.text("Connessione", language: .english), "Connection")
        XCTAssertEqual(L10n.text("Connessione", language: .italian), "Connessione")
        XCTAssertEqual(L10n.text("Connessione", language: .system, preferredLanguages: ["it-IT"]), "Connessione")
        XCTAssertEqual(L10n.text("Connessione", language: .system, preferredLanguages: ["ja-JP"]), "Connection")
        XCTAssertEqual(L10n.text("Segnalibri", language: .english, preferredLanguages: ["it-IT"]), "Bookmarks")
        XCTAssertEqual(L10n.text("Original book title", language: .english), "Original book title")
        XCTAssertEqual(L10n.text("Original book title", language: .italian), "Original book title")
    }

    func testFormattingAndCoreErrorsFollowLanguageChanges() {
        let before = L10n.language
        defer { L10n.language = before }
        L10n.language = .english
        XCTAssertEqual(L10n.format("%@ · Pagina %d", "Volume 1", 7), "Volume 1 · Page 7")
        XCTAssertEqual(L10n.format("%d di %d", 2, 13), "2 of 13")
        XCTAssertEqual(ReaderError.unavailable(503).errorDescription, "Resource unavailable (503). Try again.")
        XCTAssertEqual(ConnectionMode.automatic.label, "Automatic")
        L10n.language = .italian
        XCTAssertEqual(L10n.format("%@ · Pagina %d", "Volume 1", 7), "Volume 1 · Pagina 7")
        XCTAssertEqual(L10n.format("%d di %d", 2, 13), "2 di 13")
        XCTAssertEqual(ConnectionMode.automatic.label, "Automatico")
        XCTAssertNotEqual(ReaderError.unavailable(503).errorDescription, "Resource unavailable (503). Try again.")
    }

    func testEveryStoreLanguageIsSupportedByTheCatalogAndBundle() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("AppStore/metadata.json"))
        let metadata = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let locales = try XCTUnwrap(metadata["localizations"] as? [String: Any])
        let storeCodes = Set(locales.keys.map { String($0.split(separator: "-")[0]) })
        XCTAssertEqual(Set(AppLanguage.supportedCodes), storeCodes)
        let infoData = try Data(contentsOf: root.appendingPathComponent("App/Info.plist"))
        let info = try XCTUnwrap(PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any])
        XCTAssertEqual(Set(try XCTUnwrap(info["CFBundleLocalizations"] as? [String])), storeCodes)
        for key in L10n.english.keys {
            XCTAssertEqual(L10n.text(key, language: .italian), key)
        }
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
        let folders = [root.appendingPathComponent("App"), root.appendingPathComponent("Sources/TankarrReaderCore")]
        let files = try folders.flatMap { try FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil) }
            .filter { $0.pathExtension == "swift" }
        let expression = try NSRegularExpression(pattern: #"L10n\.(?:text|format)\("([^"\n]*)""#)
        for file in files {
            let contents = try String(contentsOf: file, encoding: .utf8)
            for match in expression.matches(in: contents, range: NSRange(contents.startIndex..., in: contents)) {
                let literal = String(contents[Range(match.range(at: 1), in: contents)!])
                let key = literal.replacingOccurrences(of: #"\n"#, with: "\n")
                XCTAssertNotNil(L10n.english[key], "Missing English translation: \(file.lastPathComponent): \(key)")
            }
        }
    }
}
