// MMRemote.m - see MMRemote.h
#import "MMRemote.h"
#import "MMSpotify.h"

#ifdef MM_MODERN
#import <UIKit/UIKit.h>
#import <SpotifyiOS/SpotifyiOS.h>

static NSString *const kEnabledKey=@"MMRemoteEnabled";
static NSString *const kTokenKey=@"MMRemoteToken";

@interface MMRemoteImpl : NSObject <SPTAppRemoteDelegate, SPTAppRemotePlayerStateDelegate>
@property (nonatomic, strong) SPTAppRemote *remote;
@property (nonatomic, copy) NSString *clientID;
@property (nonatomic, copy) NSString *wantedURI;          // the song spofity asked for
@property (nonatomic, copy) void (^pendingDone)(BOOL, NSString *);
@property (nonatomic, copy) NSString *pendingURI;         // play this once connected
@property (nonatomic, copy) NSString *stateURI;           // song the Spotify app reports
@property (nonatomic) double statePos, stateDur;          // seconds
@property (nonatomic) NSTimeInterval stateStamp;
@property (nonatomic) BOOL statePaused, ended, authorizing;
@end

static MMRemoteImpl *gImpl;

@implementation MMRemoteImpl
+ (instancetype)shared { if (!gImpl) gImpl=[MMRemoteImpl new]; return gImpl; }

- (SPTAppRemote *)remoteForClient:(NSString *)cid {
    if (self.remote && [self.clientID isEqualToString:cid]) return self.remote;
    self.clientID=cid;
    SPTConfiguration *cfg=[[SPTConfiguration alloc] initWithClientID:cid redirectURL:[NSURL URLWithString:[MMRemote redirectURI]]];
    self.remote=[[SPTAppRemote alloc] initWithConfiguration:cfg logLevel:SPTAppRemoteLogLevelInfo];
    self.remote.delegate=self;
    NSString *tok=[[NSUserDefaults standardUserDefaults] stringForKey:kTokenKey];
    if (tok.length) self.remote.connectionParameters.accessToken=tok;
    return self.remote;
}

- (void)finish:(BOOL)ok error:(NSString *)err {
    void (^d)(BOOL, NSString *)=self.pendingDone; self.pendingDone=nil;
    if (!ok && err.length) dispatch_async(dispatch_get_main_queue(), ^{   // full explanation; the bar only has room for a word
        [[[UIAlertView alloc] initWithTitle:@"Spotify app" message:err delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
    });
    if (d) dispatch_async(dispatch_get_main_queue(), ^{ d(ok, ok?nil:@"Spotify app"); });
}

- (void)authorize {
    if (self.authorizing) return;
    self.authorizing=YES;
    // Opens the Spotify app once: it asks for permission, starts the song and sends the user back here.
    [self.remote authorizeAndPlayURI:self.pendingURI?:@"" completionHandler:^(BOOL spotifyInstalled) {
        if (!spotifyInstalled) {
            self.authorizing=NO;
            [self finish:NO error:@"Install the Spotify app from the App Store: Spofity plays songs through it."];
        }
    }];
}

- (void)playPending {
    NSString *uri=self.pendingURI; if (!uri) return;
    self.pendingURI=nil;
    self.ended=NO; self.wantedURI=uri;
    [self.remote.playerAPI play:uri callback:^(id result, NSError *error) {
        if (error) { [self finish:NO error:error.localizedDescription?:@"The Spotify app couldn't play this song."]; return; }
        self.stateURI=uri; self.statePos=0; self.statePaused=NO; self.stateStamp=[NSDate timeIntervalSinceReferenceDate];
        [self finish:YES error:nil];
    }];
}

#pragma mark SPTAppRemoteDelegate
- (void)appRemoteDidEstablishConnection:(SPTAppRemote *)appRemote {
    self.authorizing=NO;
    appRemote.playerAPI.delegate=self;
    [appRemote.playerAPI subscribeToPlayerState:nil];
    [self playPending];
}
- (void)appRemote:(SPTAppRemote *)appRemote didFailConnectionAttemptWithError:(NSError *)error {
    // Token expired or the Spotify app isn't running: authorize again (only if a song is waiting).
    if (self.pendingURI) { self.authorizing=NO; [self authorize]; }
}
- (void)appRemote:(SPTAppRemote *)appRemote didDisconnectWithError:(NSError *)error {}

#pragma mark Player state
- (void)playerStateDidChange:(id<SPTAppRemotePlayerState>)st {
    NSString *uri=st.track.URI;
    BOOL wasOurs=self.wantedURI && [self.stateURI isEqualToString:self.wantedURI];
    self.stateURI=uri;
    self.statePos=st.playbackPosition/1000.0;
    self.stateDur=st.track.duration/1000.0;
    self.statePaused=st.isPaused;
    self.stateStamp=[NSDate timeIntervalSinceReferenceDate];
    // The Spotify app moved on from spofity's song (it ended): let spofity's own queue pick the next one.
    if (wasOurs && uri && self.wantedURI && ![uri isEqualToString:self.wantedURI] && !self.ended) {
        self.ended=YES;
        [[NSNotificationCenter defaultCenter] postNotificationName:@"MMAudioDidFinish" object:nil];
    }
}
@end

@implementation MMRemote
+ (BOOL)available { return YES; }
+ (BOOL)enabled { return [[NSUserDefaults standardUserDefaults] boolForKey:kEnabledKey]; }
+ (void)setEnabled:(BOOL)on { [[NSUserDefaults standardUserDefaults] setBool:on forKey:kEnabledKey]; [[NSUserDefaults standardUserDefaults] synchronize]; }
+ (NSString *)redirectURI { return @"spofity://spotify-login-callback"; }

+ (BOOL)handleURL:(NSURL *)url {
    if (![url.scheme isEqualToString:@"spofity"]) return NO;
    MMRemoteImpl *m=[MMRemoteImpl shared];
    m.authorizing=NO;
    if (!m.remote) return YES;
    NSDictionary *p=[m.remote authorizationParametersFromURL:url];
    NSString *tok=p[SPTAppRemoteAccessTokenKey];
    if (tok.length) {
        [[NSUserDefaults standardUserDefaults] setObject:tok forKey:kTokenKey];
        m.remote.connectionParameters.accessToken=tok;
        // authorizeAndPlayURI already started the song in the Spotify app; connecting just takes over control.
        if (m.pendingURI) { m.wantedURI=m.pendingURI; m.pendingURI=nil; m.ended=NO; [m finish:YES error:nil]; }
        [m.remote connect];
    } else {
        NSString *err=p[SPTAppRemoteErrorDescriptionKey]?:@"Spotify didn't allow access.";
        [m finish:NO error:[err stringByAppendingFormat:@"\n\nIn your Spotify developer app, add the redirect URI %@ and the iOS bundle ID %@.",
                            [self redirectURI],[NSBundle mainBundle].bundleIdentifier]];
    }
    return YES;
}

+ (void)appDidBecomeActive {
    MMRemoteImpl *m=gImpl;
    if (m.remote && !m.remote.isConnected && m.remote.connectionParameters.accessToken.length) [m.remote connect];
}

+ (void)playTrack:(NSString *)trackId completion:(void (^)(BOOL, NSString *))done {
    NSString *cid=[MMSpotify searchKeyId];
    if (!cid.length) { if (done) done(NO,@"Set up your Spotify developer key first (Settings → Unlock search). Spofity uses it to play through the Spotify app."); return; }
    MMRemoteImpl *m=[MMRemoteImpl shared];
    SPTAppRemote *r=[m remoteForClient:cid];
    NSString *uri=[@"spotify:track:" stringByAppendingString:trackId];
    if (m.pendingDone) [m finish:NO error:nil];   // an older request is superseded
    m.pendingDone=done; m.pendingURI=uri;
    if (r.isConnected) [m playPending];
    else if (r.connectionParameters.accessToken.length) [r connect];   // fails over to authorize in the delegate
    else [m authorize];
}

+ (BOOL)isPlaying { MMRemoteImpl *m=gImpl; return m.remote.isConnected && m.stateURI && !m.statePaused && !m.ended; }
+ (BOOL)hasEnded { return gImpl.ended; }
+ (double)duration { return gImpl.stateDur; }
+ (double)currentTime {
    MMRemoteImpl *m=gImpl; if (!m) return 0;
    double t=m.statePos;
    if (!m.statePaused) t+=[NSDate timeIntervalSinceReferenceDate]-m.stateStamp;
    if (m.stateDur>0 && t>m.stateDur) t=m.stateDur;
    return MAX(0,t);
}
+ (void)setPaused:(BOOL)paused {
    MMRemoteImpl *m=gImpl; if (!m.remote.isConnected) { if (!paused && m.wantedURI) [m.remote connect]; return; }
    m.statePos=[self currentTime]; m.stateStamp=[NSDate timeIntervalSinceReferenceDate]; m.statePaused=paused;
    if (paused) [m.remote.playerAPI pause:nil]; else [m.remote.playerAPI resume:nil];
}
+ (void)seekTo:(double)s {
    MMRemoteImpl *m=gImpl; if (!m.remote.isConnected) return;
    m.statePos=s; m.stateStamp=[NSDate timeIntervalSinceReferenceDate];
    [m.remote.playerAPI seekToPosition:(NSInteger)(s*1000) callback:nil];
}
+ (void)stop { MMRemoteImpl *m=gImpl; if (m.remote.isConnected) [m.remote.playerAPI pause:nil]; m.statePaused=YES; }
@end

#else
@implementation MMRemote
+ (BOOL)available { return NO; }
+ (BOOL)enabled { return NO; }
+ (void)setEnabled:(BOOL)on {}
+ (NSString *)redirectURI { return nil; }
+ (BOOL)handleURL:(NSURL *)url { return NO; }
+ (void)appDidBecomeActive {}
+ (void)playTrack:(NSString *)trackId completion:(void (^)(BOOL, NSString *))done { if (done) done(NO,nil); }
+ (BOOL)isPlaying { return NO; }
+ (BOOL)hasEnded { return NO; }
+ (double)currentTime { return 0; }
+ (double)duration { return 0; }
+ (void)setPaused:(BOOL)paused {}
+ (void)seekTo:(double)seconds {}
+ (void)stop {}
@end
#endif
