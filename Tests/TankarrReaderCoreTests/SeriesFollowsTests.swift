import XCTest
@testable import TankarrReaderCore

final class SeriesFollowsTests: XCTestCase {
    func testFollowingProtocolAndLegacyGateway() throws {
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(FollowsResponse.self, from: Data(#"{"items":[{"series_id":"source.series","followed_at":1234}]}"#.utf8))
        XCTAssertEqual(response.items, [FollowedSeries(seriesId: "source.series", followedAt: 1234)])
        let old = try decoder.decode(ReaderStatus.self, from: Data(#"{"name":"Reader","api_version":1,"read_only":true,"instance_id":"fixture"}"#.utf8))
        XCTAssertNil(old.followingWritable)
        XCTAssertNil(old.pushNotificationsAvailable)
    }

    func testOnlyFixedFollowingAndDeviceRoutesAreWritable() throws {
        let base = try Endpoint.validate("https://reader.example.org")
        let device = UUID().uuidString
        for path in ["/v1/series/source.series/follow", "/v1/notifications/devices/\(device)"] {
            let request = try Endpoint.request(base: base, path: path, username: "reader", password: "fixture-password",
                                               method: "PUT", jsonBody: Data("{}".utf8))
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Tankarr-Reader"), "1")
            XCTAssertNil(request.value(forHTTPHeaderField: "X-Api-Key"))
            XCTAssertThrowsError(try Endpoint.request(base: base, path: path, username: "reader", password: "fixture-password",
                                                       method: "POST", jsonBody: Data("{}".utf8)))
        }
        for path in ["/v1/series/../follow", "/v1/series/x/follow?user=other", "/v1/notifications/devices/../settings",
                     "/api/manga/x", "/v1/notifications/send", "/v1/library"] {
            XCTAssertThrowsError(try Endpoint.request(base: base, path: path, username: "reader", password: "fixture-password",
                                                       method: "PUT", jsonBody: Data("{}".utf8)))
        }
    }

    func testPushNavigationCannotCrossServersOrAccountsOrOpenLinks() {
        var payload: [AnyHashable: Any] = ["series_id": "source.series", "instance_id": "server-1", "reader_account": "reader"]
        XCTAssertEqual(ChapterNotification(payload: payload, instance: "server-1", username: "reader")?.seriesID, "source.series")
        XCTAssertNil(ChapterNotification(payload: payload, instance: "server-2", username: "reader"))
        XCTAssertNil(ChapterNotification(payload: payload, instance: "server-1", username: "other"))
        XCTAssertNil(ChapterNotification(payload: payload, instance: nil, username: "reader"))
        payload["series_id"] = "https://other.example/"
        XCTAssertNil(ChapterNotification(payload: payload, instance: "server-1", username: "reader"))
        payload["series_id"] = "../settings"
        XCTAssertNil(ChapterNotification(payload: payload, instance: "server-1", username: "reader"))
    }
}
