import Foundation

/// Portable preferences, never credentials, APNs tokens, files or pending writes.
public struct ReaderConfiguration: Codable, Equatable {
    public static let formatName = "tankarr-reader"
    public static let maximumBytes = 512 * 1024
    public let format: String
    public let version: Int
    public var profile: ServerProfile
    public var appLanguage: AppLanguage
    public var readingOptions: [String: ReadingOptions]
    public var followedSeries: [String]

    public init(profile: ServerProfile, appLanguage: AppLanguage = .system,
                readingOptions: [String: ReadingOptions] = [:], followedSeries: [String] = []) {
        format = Self.formatName; version = 1; self.profile = profile
        self.appLanguage = appLanguage; self.readingOptions = readingOptions
        self.followedSeries = followedSeries.sorted()
    }
    public func validate() throws {
        guard format == Self.formatName, version == 1,
              !profile.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              profile.username.count <= 200, readingOptions.count <= 5000, followedSeries.count <= 5000,
              profile.instanceID == nil || (1...160).contains(profile.instanceID!.count) else {
            throw ReaderError.invalidAccount
        }
        _ = try profile.candidates()
        for address in [profile.localAddress, profile.remoteAddress] where !address.isEmpty {
            _ = try Endpoint.validate(address)
        }
        for id in Array(readingOptions.keys) + followedSeries { _ = try Endpoint.identifier(id) }
    }
    public func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumBytes else { throw ReaderError.invalidAccount }
        return data
    }
    public func matchesAccount(_ current: ServerProfile) -> Bool {
        guard let instance = profile.instanceID else { return false }
        return instance == current.instanceID && profile.username == current.username
    }
    public func canReusePassword(from current: ServerProfile) -> Bool {
        // The instance in an imported file is a claim, not proof of its origin.
        // Never autofill a stored password into a newly supplied endpoint.
        func endpoints(_ value: ServerProfile) -> Set<URL>? {
            let addresses = [value.localAddress, value.remoteAddress].filter {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return try? Set(addresses.map { try Endpoint.validate($0) })
        }
        guard matchesAccount(current), let requested = endpoints(profile), !requested.isEmpty,
              let configured = endpoints(current) else { return false }
        return requested.isSubset(of: configured)
    }
}

public struct ImportedReaderConfiguration {
    public let configuration: ReaderConfiguration
    /// Only legacy connection files may contain a password; exports never do.
    public let password: String?
    public let includesPreferences: Bool

    public init(data: Data) throws {
        guard data.count <= ReaderConfiguration.maximumBytes else { throw ReaderError.invalidAccount }
        let decoder = JSONDecoder()
        struct Format: Decodable { let format: String?; let version: Int? }
        let marker = try decoder.decode(Format.self, from: data)
        if marker.format != nil || marker.version != nil {
            configuration = try decoder.decode(ReaderConfiguration.self, from: data)
            password = nil; includesPreferences = true
        } else {
            struct Legacy: Decodable {
                let localAddress: String?; let remoteAddress: String; let username: String
                let password: String?; let instanceID: String?; let mode: ConnectionMode?
            }
            let legacy = try decoder.decode(Legacy.self, from: data)
            configuration = ReaderConfiguration(profile: ServerProfile(localAddress: legacy.localAddress ?? "",
                remoteAddress: legacy.remoteAddress, username: legacy.username,
                mode: legacy.mode ?? .automatic, instanceID: legacy.instanceID))
            password = legacy.password; includesPreferences = false
        }
        try configuration.validate()
    }
}

public enum ReaderCancellation {
    public static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }
}
