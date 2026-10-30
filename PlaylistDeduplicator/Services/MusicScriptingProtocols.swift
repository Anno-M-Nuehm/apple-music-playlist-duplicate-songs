import Foundation
import ScriptingBridge

/// Minimal, hand-written ScriptingBridge protocol declarations for the
/// subset of Music's scripting surface this app needs. Selector names
/// (persistentID, name, artist, …) map at runtime to Music's sdef codes.

@objc protocol MusicItemProtocol: SBObjectProtocol {}

@objc protocol MusicTrackProtocol: MusicItemProtocol {
    var persistentID: String? { get }
    var name: String? { get }
    var artist: String? { get }
    var album: String? { get }
    var duration: Double { get }
    var location: URL? { get }
}

@objc protocol MusicPlaylistProtocol: MusicItemProtocol {
    var id: Int { get }
    var name: String? { get }
    var smart: Bool { get }
    var tracks: SBElementArray? { get }
}

@objc protocol MusicApplicationProtocol: SBApplicationProtocol {
    var name: String? { get }
    var playlists: SBElementArray? { get }
    @objc optional func open(_ x: [Any]!)
}
