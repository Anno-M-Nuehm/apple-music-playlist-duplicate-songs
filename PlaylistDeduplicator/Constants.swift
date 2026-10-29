import Foundation

/// The ONLY file in the target containing hard-coded literals.
/// All values defined here are defaults; runtime-tunable values are
/// overridden by the bundled `config.json` (see `ConfigStore`).
enum Constants {
    enum DuplicateDetection {
        static let defaultDurationToleranceSeconds: Double = 2.0
        static let matchByPersistentIDFirst = true
    }

    enum Playlists {
        static let defaultExcludedNames: Set<String> = ["Music", "Movies", "TV Shows", "Podcasts", "Audiobooks"]
        static let includeSmartPlaylists = false
    }

    enum AIAssist {
        static let enabled = true
        static let defaultEndpoint = "https://api.openai.com/v1/chat/completions"
        static let defaultModel = "gpt-4o-mini"
        static let timeoutSeconds: TimeInterval = 20
        static let keychainService = "com.example.PlaylistDeduplicator.ai"
        static let keychainAccount = "ai-api-key"
    }

    enum App {
        static let musicAppBundleID = "com.apple.Music"
        static let appleEventsUsageDescription = "Playlist Deduplicator needs to send Apple Events to Music to read your playlists and remove duplicate entries from a playlist you select."
        static let musicAccessErrorDomain = "com.example.PlaylistDeduplicator.music"
    }

    enum Export {
        static let defaultFormat = "csv"
        static let reportColumns = ["group", "title", "artist", "album", "duration", "persistentID", "occurrences", "selectedForRemoval"]
    }
}
