/*
 * Generated/Music.h — ScriptingBridge interface for Music.app
 *
 * Minimal header in the exact shape `sdp -fh --basename Music` produces
 * for the subset of Music's dictionary this app uses. ScriptingBridge
 * headers contain *declarations only*: SBObject/SBApplication provide
 * the implementations at runtime, matching selector names (userPlaylists,
 * tracks, persistentID, …) against the target application's sdef. No code
 * is linked from this file.
 *
 * To regenerate the full header from your system's Music.app instead:
 *   ./Scripts/generate-music-header.sh
 */

#import <Foundation/Foundation.h>
#import <ScriptingBridge/ScriptingBridge.h>

@class MusicItem, MusicApplication, MusicPlaylist, MusicUserPlaylist, MusicTrack;

@interface MusicItem : SBObject
@end

@interface MusicApplication : SBApplication
@property (readonly) SBElementArray *userPlaylists;
@property (copy, readonly) NSString *name;
- (void)open:(NSArray<NSURL *> *)x;
@end

@interface MusicPlaylist : MusicItem
@property (readonly) SBElementArray *tracks;
@property (readonly) NSInteger id;
@property (copy) NSString *name;
@property (readonly) BOOL smart;
@end

@interface MusicUserPlaylist : MusicPlaylist
@end

@interface MusicTrack : MusicItem
@property (copy, readonly) NSString *persistentID;
@property (copy) NSString *name;
@property (copy) NSString *artist;
@property (copy) NSString *album;
@property double duration;
@property (copy) NSURL *location;
@end
