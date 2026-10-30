import Foundation
import ScriptingBridge

/// Minimal, hand-written ScriptingBridge protocol declarations for the
/// subset of Music's scripting surface this app needs.
///
/// SBObject resolves any ObjC property selector dynamically (it
/// conforms to arbitrary protocols at runtime), so the base protocol
/// only needs to be `NSObjectProtocol` — the SB-specific marker
/// protocols are not required and are not exposed uniformly across
/// SDKs. Property names (persistentID, name, artist, …) map at runtime
/// to Music's sdef codes.

@objc protocol MusicItemProtocol: NSObjectProtocol {}

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

@objc protocol MusicApplicationProtocol: NSObjectProtocol {
    var name: String? { get }
    var playlists: SBElementArray? { get }
    @objc optional func open(_ x: [Any]!)
}
