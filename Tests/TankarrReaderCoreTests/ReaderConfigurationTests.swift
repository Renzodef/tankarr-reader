import Foundation
import XCTest
@testable import TankarrReaderCore

final class ReaderConfigurationTests: XCTestCase {
    private let profile = ServerProfile(localAddress: "http://nas.local:8789", remoteAddress: "https://reader.example.org",
        username: "reader", mode: .remote, instanceID: "fixture-instance")

    func testPortablePreferencesRoundTripWithoutCredentialsOrDeviceIdentity() throws {
        let value = ReaderConfiguration(profile: profile, appLanguage: .english,
            readingOptions: ["book-2": ReadingOptions(direction: .rtl, layout: .continuous, axis: .horizontal)],
            followedSeries: ["series-2", "series-1"])
        let data = try value.encoded()
        let raw = String(decoding: data, as: UTF8.self)
        for forbidden in ["password", "token", "installation", "page_index", "pending", "downloadEndpoint"] {
            XCTAssertFalse(raw.contains(forbidden))
        }
        let imported = try ImportedReaderConfiguration(data: data)
        XCTAssertEqual(imported.configuration, value)
        XCTAssertTrue(imported.includesPreferences)
        XCTAssertNil(imported.password)
        XCTAssertEqual(imported.configuration.profile.mode, .remote)
    }

    func testAllLanguageChoicesRoundTripWithoutLosingPreferences() throws {
        for language in AppLanguage.allCases {
            let value = ReaderConfiguration(profile: profile, appLanguage: language,
                readingOptions: ["book-2": ReadingOptions(direction: .rtl, layout: .continuous, axis: .horizontal)],
                followedSeries: ["series-1"])
            let imported = try ImportedReaderConfiguration(data: value.encoded())
            XCTAssertEqual(imported.configuration, value)
        }
    }

    func testUnknownLanguageDoesNotSilentlyReplaceImportedPreferences() throws {
        var object = try JSONSerialization.jsonObject(with: ReaderConfiguration(profile: profile).encoded()) as! [String: Any]
        object["appLanguage"] = "unsupported"
        XCTAssertThrowsError(try ImportedReaderConfiguration(data: JSONSerialization.data(withJSONObject: object)))
    }

    func testLegacyConnectionFileStillImportsButPasswordNeverExports() throws {
        let raw = #"{"remoteAddress":"https://reader.example.org","username":"reader","password":"fixture-password"}"#
        let value = try ImportedReaderConfiguration(data: Data(raw.utf8))
        XCTAssertEqual(value.password, "fixture-password")
        XCTAssertFalse(value.includesPreferences)
        XCTAssertEqual(value.configuration.profile.mode, .automatic)
        XCTAssertFalse(String(decoding: try value.configuration.encoded(), as: UTF8.self).contains("fixture-password"))
    }

    func testAccountPreferencesRequireMatchingKnownInstanceAndUser() {
        let value = ReaderConfiguration(profile: profile)
        XCTAssertTrue(value.matchesAccount(profile))
        var other = profile; other.username = "another-reader"
        XCTAssertFalse(value.matchesAccount(other))
        other = profile; other.instanceID = "another-server"
        XCTAssertFalse(value.matchesAccount(other))
        other = profile; other.instanceID = nil
        XCTAssertFalse(ReaderConfiguration(profile: other).matchesAccount(other))
    }

    func testImportedIdentityCannotAutofillPasswordToAnUnconfiguredEndpoint() {
        let own = ReaderConfiguration(profile: profile)
        XCTAssertTrue(own.canReusePassword(from: profile))
        var untrusted = profile; untrusted.remoteAddress = "https://unconfigured.example.org"
        let claimed = ReaderConfiguration(profile: untrusted)
        XCTAssertTrue(claimed.matchesAccount(profile), "A file can copy the public identity fields")
        XCTAssertFalse(claimed.canReusePassword(from: profile))
        untrusted = profile
        untrusted.localAddress = "http://unconfigured.local:8789"
        XCTAssertFalse(ReaderConfiguration(profile: untrusted).canReusePassword(from: profile),
                       "An unused new address must not receive the password after a mode switch")
        untrusted.mode = .automatic
        XCTAssertFalse(ReaderConfiguration(profile: untrusted).canReusePassword(from: profile))
        untrusted = profile; untrusted.remoteAddress += "/different-reader"
        XCTAssertFalse(ReaderConfiguration(profile: untrusted).canReusePassword(from: profile))
        untrusted = profile; untrusted.username = "another-reader"
        XCTAssertFalse(ReaderConfiguration(profile: untrusted).canReusePassword(from: profile))
    }

    func testRejectsUnknownFormatVersionOversizeAndUnsafeResourceIDs() throws {
        let valid = try ReaderConfiguration(profile: profile).encoded()
        for (from, to) in [("tankarr-reader", "other-app"), ("\"version\" : 1", "\"version\" : 2")] {
            let invalid = String(decoding: valid, as: UTF8.self).replacingOccurrences(of: from, with: to)
            XCTAssertThrowsError(try ImportedReaderConfiguration(data: Data(invalid.utf8)))
        }
        XCTAssertThrowsError(try ImportedReaderConfiguration(data: Data(repeating: 32, count: ReaderConfiguration.maximumBytes + 1)))
        XCTAssertThrowsError(try ReaderConfiguration(profile: profile, followedSeries: ["../admin"]).encoded())
        XCTAssertThrowsError(try ReaderConfiguration(profile: profile, readingOptions: ["book/elsewhere": ReadingOptions()]).encoded())
        var unsafe = profile; unsafe.localAddress = "http://public.example.org"
        XCTAssertThrowsError(try ReaderConfiguration(profile: unsafe).encoded(), "Even unused addresses must be safe")
    }

    func testReadingOptionExportIsScopedAndImportMergesWithoutClearingOtherBooks() throws {
        let suite = "ReaderConfigurationTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = ReadingPreferences(defaults: defaults)
        let rtl = ReadingOptions(direction: .rtl, layout: .paged)
        let vertical = ReadingOptions(layout: .continuous, axis: .vertical)
        preferences.save(rtl, book: "first", instance: "server-a")
        preferences.save(vertical, book: "private-other-server", instance: "server-b")
        XCTAssertEqual(preferences.snapshot(instance: "server-a"), ["first": rtl])
        try preferences.merge(["second": vertical], instance: "server-a")
        XCTAssertEqual(preferences.snapshot(instance: "server-a"), ["first": rtl, "second": vertical])
        XCTAssertEqual(preferences.snapshot(instance: "server-b"), ["private-other-server": vertical])
        XCTAssertThrowsError(try preferences.merge(["../bad": rtl], instance: "server-a"))
    }

    func testCancelledRefreshIsNotAConnectionFailure() {
        XCTAssertTrue(ReaderCancellation.isCancellation(CancellationError()))
        XCTAssertTrue(ReaderCancellation.isCancellation(URLError(.cancelled)))
        for error: Error in [URLError(.timedOut), URLError(.serverCertificateUntrusted), ReaderError.unauthorized] {
            XCTAssertFalse(ReaderCancellation.isCancellation(error))
        }
    }
}
