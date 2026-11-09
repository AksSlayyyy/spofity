// MMRemote.h - plays songs through the official Spotify app (Spotify iOS SDK, App Remote). Modern builds only.
// Spotify refuses song keys to newer accounts in third-party players; the official app plays any Premium account.
// Spofity stays the interface (library, queue, player, Cover Flow); the Spotify app makes the sound.
#import <Foundation/Foundation.h>

@interface MMRemote : NSObject
+ (BOOL)available;                 // compiled in (modern build)
+ (BOOL)enabled;                   // songs go through the Spotify app
+ (void)setEnabled:(BOOL)on;
+ (NSString *)redirectURI;         // to add in the Spotify developer dashboard
+ (BOOL)handleURL:(NSURL *)url;    // return from the Spotify app after authorizing
+ (void)appDidBecomeActive;

+ (void)playTrack:(NSString *)trackId completion:(void (^)(BOOL ok, NSString *error))done;
+ (BOOL)isPlaying;
+ (BOOL)hasEnded;
+ (double)currentTime;
+ (double)duration;
+ (void)setPaused:(BOOL)paused;
+ (void)seekTo:(double)seconds;
+ (void)stop;
@end
