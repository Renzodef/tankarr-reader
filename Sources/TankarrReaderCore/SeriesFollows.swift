import Foundation

public struct FollowedSeries: Codable, Identifiable, Equatable, Sendable {
    public let seriesId: String
    public let followedAt: Double
    public var id: String { seriesId }
    public init(seriesId: String, followedAt: Double) {
        self.seriesId = seriesId; self.followedAt = followedAt
    }
}

public struct FollowsResponse: Codable, Sendable {
    public let items: [FollowedSeries]
}

public enum PushEnvironment: String, Codable, Sendable {
    case production, sandbox
}

/// A notification can only navigate within its original authenticated account.
/// Server URLs, commands and arbitrary links in a payload are never followed.
public struct ChapterNotification: Equatable, Sendable {
    public let seriesID: String
    public init?(payload: [AnyHashable: Any], instance: String?, username: String) {
        guard let instance, !instance.isEmpty,
              payload["instance_id"] as? String == instance,
              payload["reader_account"] as? String == username,
              let sid = payload["series_id"] as? String,
              (try? Endpoint.identifier(sid)) != nil else { return nil }
        seriesID = sid
    }
}

public extension ReaderAPI {
    func follows() async throws -> [FollowedSeries] {
        let response: FollowsResponse = try await get("/v1/follows")
        return response.items
    }
    func setFollowing(_ following: Bool, series: String) async throws -> [FollowedSeries] {
        let path = "/v1/series/\(try Endpoint.identifier(series))/follow"
        let payload = try await data(path, method: following ? "PUT" : "DELETE",
                                  jsonBody: following ? Data("{}".utf8) : nil)
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(FollowsResponse.self, from: payload).items
    }
    func registerPush(device: UUID, token: String, environment: PushEnvironment, language: String) async throws {
        struct Registration: Encodable {
            let token: String
            let environment: String
            let language: String
        }
        let value = Registration(token: token, environment: environment.rawValue, language: language == "it" ? "it" : "en")
        _ = try await data("/v1/notifications/devices/\(device.uuidString)", timeout: 8, method: "PUT",
                           jsonBody: JSONEncoder().encode(value))
    }
    func unregisterPush(device: UUID) async throws {
        _ = try await data("/v1/notifications/devices/\(device.uuidString)", timeout: 8, method: "DELETE")
    }
}
