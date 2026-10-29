import Foundation

/// Loads tunable settings from the bundled `config.json`,
/// falling back to `Constants` defaults for any missing key.
struct AppConfig: Sendable, Equatable {
    struct DuplicateDetection: Sendable, Equatable {
        var durationToleranceSeconds: Double
        var matchByPersistentIDFirst: Bool
        var caseInsensitiveTextMatch: Bool

        static let defaults = DuplicateDetection(
            durationToleranceSeconds: Constants.DuplicateDetection.defaultDurationToleranceSeconds,
            matchByPersistentIDFirst: Constants.DuplicateDetection.matchByPersistentIDFirst,
            caseInsensitiveTextMatch: true
        )
    }

    struct Playlists: Sendable, Equatable {
        var excludedNames: Set<String>
        var includeSmartPlaylists: Bool

        static let defaults = Playlists(
            excludedNames: Constants.Playlists.defaultExcludedNames,
            includeSmartPlaylists: Constants.Playlists.includeSmartPlaylists
        )
    }

    struct AIAssist: Sendable, Equatable {
        var enabled: Bool
        var endpoint: String
        var model: String
        var timeoutSeconds: TimeInterval
        var keychainService: String
        var keychainAccount: String

        static let defaults = AIAssist(
            enabled: Constants.AIAssist.enabled,
            endpoint: Constants.AIAssist.defaultEndpoint,
            model: Constants.AIAssist.defaultModel,
            timeoutSeconds: Constants.AIAssist.timeoutSeconds,
            keychainService: Constants.AIAssist.keychainService,
            keychainAccount: Constants.AIAssist.keychainAccount
        )
    }

    struct Export: Sendable, Equatable {
        var defaultFormat: String
        var reportColumns: [String]

        static let defaults = Export(
            defaultFormat: Constants.Export.defaultFormat,
            reportColumns: Constants.Export.reportColumns
        )
    }

    var duplicateDetection: DuplicateDetection
    var playlists: Playlists
    var aiAssist: AIAssist
    var export: Export

    static let defaults = AppConfig(
        duplicateDetection: .defaults,
        playlists: .defaults,
        aiAssist: .defaults,
        export: .defaults
    )
}

enum ConfigStore {
    enum ConfigError: Error { case invalidJSON }

    static func load(bundle: Bundle = .main) -> AppConfig {
        guard let url = bundle.url(forResource: "config", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return .defaults
        }
        return load(from: data) ?? .defaults
    }

    static func load(from data: Data) -> AppConfig? {
        struct Root: Decodable {
            var duplicateDetection: Duplicate?
            var playlists: Playlists?
            var aiAssist: AI?
            var export: Export?
        }
        struct Duplicate: Decodable {
            var durationToleranceSeconds: Double?
            var matchByPersistentIDFirst: Bool?
            var caseInsensitiveTextMatch: Bool?
        }
        struct Playlists: Decodable {
            var excludedNames: [String]?
            var includeSmartPlaylists: Bool?
        }
        struct AI: Decodable {
            var enabled: Bool?
            var endpoint: String?
            var model: String?
            var timeoutSeconds: TimeInterval?
            var keychainService: String?
            var keychainAccount: String?
        }
        struct Export: Decodable {
            var defaultFormat: String?
            var reportColumns: [String]?
        }
        guard let root = try? JSONDecoder().decode(Root.self, from: data) else { return nil }

        var config = AppConfig.defaults
        if let d = root.duplicateDetection {
            config.duplicateDetection.durationToleranceSeconds = d.durationToleranceSeconds ?? config.duplicateDetection.durationToleranceSeconds
            config.duplicateDetection.matchByPersistentIDFirst = d.matchByPersistentIDFirst ?? config.duplicateDetection.matchByPersistentIDFirst
            config.duplicateDetection.caseInsensitiveTextMatch = d.caseInsensitiveTextMatch ?? config.duplicateDetection.caseInsensitiveTextMatch
        }
        if let p = root.playlists {
            config.playlists.excludedNames = Set(p.excludedNames ?? Array(config.playlists.excludedNames))
            config.playlists.includeSmartPlaylists = p.includeSmartPlaylists ?? config.playlists.includeSmartPlaylists
        }
        if let ai = root.aiAssist {
            config.aiAssist.enabled = ai.enabled ?? config.aiAssist.enabled
            config.aiAssist.endpoint = ai.endpoint ?? config.aiAssist.endpoint
            config.aiAssist.model = ai.model ?? config.aiAssist.model
            config.aiAssist.timeoutSeconds = ai.timeoutSeconds ?? config.aiAssist.timeoutSeconds
            config.aiAssist.keychainService = ai.keychainService ?? config.aiAssist.keychainService
            config.aiAssist.keychainAccount = ai.keychainAccount ?? config.aiAssist.keychainAccount
        }
        if let e = root.export {
            config.export.defaultFormat = e.defaultFormat ?? config.export.defaultFormat
            config.export.reportColumns = e.reportColumns ?? config.export.reportColumns
        }
        return config
    }
}
