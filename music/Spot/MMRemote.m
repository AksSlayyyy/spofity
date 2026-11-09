// MMRemote.m - see MMRemote.h
#import "MMRemote.h"
#import "MMSpotify.h"

#ifdef MM_MODERN
#import <UIKit/UIKit.h>
#import <SpotifyiOS/SpotifyiOS.h>
#import <AuthenticationServices/AuthenticationServices.h>
#import <CommonCrypto/CommonDigest.h>

static NSString *const kEnabledKey=@"MMRemoteEnabled";
static NSString *const kTokenKey=@"MMRemoteToken";
static NSString *const kRefreshKey=@"MMRemoteRefresh";
static NSString *const kExpiryKey=@"MMRemoteExpiry";
static NSString *const kScopes=@"app-remote-control user-modify-playback-state user-read-playback-state user-read-currently-playing";

static NSString *b64url(NSData *d) {
    return [[[[d base64EncodedStringWithOptions:0] stringByReplacingOccurrencesOfString:@"+" withString:@"-"]
             stringByReplacingOccurrencesOfString:@"/" withString:@"_"] stringByReplacingOccurrencesOfString:@"=" withString:@""];
}
static NSString *formEnc(NSString *s) {
    NSMutableCharacterSet *ok=[[NSCharacterSet alphanumericCharacterSet] mutableCopy]; [ok addCharactersInString:@"-._~"];
    return [s stringByAddingPercentEncodingWithAllowedCharacters:ok];
}

@interface MMRemoteImpl : NSObject <SPTAppRemoteDelegate, SPTAppRemotePlayerStateDelegate, ASWebAuthenticationPresentationContextProviding>
@property (nonatomic, strong) ASWebAuthenticationSession *webAuth;
@property (nonatomic) BOOL triedAppAuthorize;
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

#pragma mark In-app Spotify login (PKCE) - no browser, no Spotify-app approval page

- (ASPresentationAnchor)presentationAnchorForWebAuthenticationSession:(ASWebAuthenticationSession *)session {
    for (UIWindow *w in [UIApplication sharedApplication].windows) if (w.isKeyWindow) return w;
    return [UIApplication sharedApplication].windows.firstObject;
}

- (void)saveTokenJSON:(NSDictionary *)j {
    NSUserDefaults *u=[NSUserDefaults standardUserDefaults];
    if ([j[@"access_token"] length]) [u setObject:j[@"access_token"] forKey:kTokenKey];
    if ([j[@"refresh_token"] length]) [u setObject:j[@"refresh_token"] forKey:kRefreshKey];
    [u setDouble:[NSDate timeIntervalSinceReferenceDate]+MAX(60,[j[@"expires_in"] doubleValue])-120 forKey:kExpiryKey];
    [u synchronize];
}

- (void)tokenRequest:(NSString *)body done:(void (^)(NSString *tok, NSString *err))done {
    NSMutableURLRequest *rq=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://accounts.spotify.com/api/token"]];
    rq.HTTPMethod=@"POST"; rq.HTTPBody=[body dataUsingEncoding:NSUTF8StringEncoding];
    [rq setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    [[[NSURLSession sharedSession] dataTaskWithRequest:rq completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        NSDictionary *j=d?[NSJSONSerialization JSONObjectWithData:d options:0 error:NULL]:nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([j isKindOfClass:[NSDictionary class]] && [j[@"access_token"] length]) { [self saveTokenJSON:j]; done(j[@"access_token"],nil); }
            else done(nil,[NSString stringWithFormat:@"Spotify login failed: %@",
                           ([j isKindOfClass:[NSDictionary class]]?(j[@"error_description"]?:j[@"error"]):nil)?:e.localizedDescription?:@"no answer"]);
        });
    }] resume];
}

// A valid access token: stored, refreshed, or from a new in-app login.
- (void)withToken:(void (^)(NSString *tok, NSString *err))done {
    NSUserDefaults *u=[NSUserDefaults standardUserDefaults];
    NSString *tok=[u stringForKey:kTokenKey], *ref=[u stringForKey:kRefreshKey];
    if (tok.length && [u doubleForKey:kExpiryKey]>[NSDate timeIntervalSinceReferenceDate]) { done(tok,nil); return; }
    if (ref.length) {
        [self tokenRequest:[NSString stringWithFormat:@"grant_type=refresh_token&refresh_token=%@&client_id=%@",formEnc(ref),formEnc(self.clientID)]
                      done:^(NSString *t, NSString *err) { if (t) done(t,nil); else { [u removeObjectForKey:kRefreshKey]; [self webLogin:done]; } }];
        return;
    }
    [self webLogin:done];
}

- (void)webLogin:(void (^)(NSString *tok, NSString *err))done {
    if (self.webAuth) return;
    unsigned char rnd[48]; arc4random_buf(rnd,sizeof rnd);
    NSString *verifier=b64url([NSData dataWithBytes:rnd length:sizeof rnd]);
    NSData *vd=[verifier dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char sha[CC_SHA256_DIGEST_LENGTH]; CC_SHA256(vd.bytes,(CC_LONG)vd.length,sha);
    NSString *challenge=b64url([NSData dataWithBytes:sha length:sizeof sha]);
    NSString *redirect=[MMRemote redirectURI];
    NSString *url=[NSString stringWithFormat:@"https://accounts.spotify.com/authorize?client_id=%@&response_type=code&redirect_uri=%@&scope=%@&code_challenge_method=S256&code_challenge=%@",
                   formEnc(self.clientID),formEnc(redirect),formEnc(kScopes),challenge];
    __weak MMRemoteImpl *ws=self;
    self.webAuth=[[ASWebAuthenticationSession alloc] initWithURL:[NSURL URLWithString:url] callbackURLScheme:@"spofity"
                                               completionHandler:^(NSURL *cb, NSError *e) {
        dispatch_async(dispatch_get_main_queue(), ^{
            MMRemoteImpl *ss=ws; ss.webAuth=nil;
            NSString *code=nil, *err=nil;
            for (NSURLQueryItem *q in [NSURLComponents componentsWithURL:cb resolvingAgainstBaseURL:NO].queryItems) {
                if ([q.name isEqualToString:@"code"]) code=q.value;
                if ([q.name isEqualToString:@"error"]) err=q.value;
            }
            if (!code) {
                if (e.code==ASWebAuthenticationSessionErrorCodeCanceledLogin) { done(nil,nil); return; }   // user closed it
                done(nil,[NSString stringWithFormat:@"Spotify login didn't finish (%@).\n\nCheck your Spotify developer app: Redirect URI %@ must be added and saved.",
                          err?:e.localizedDescription?:@"no code",redirect]);
                return;
            }
            [ss tokenRequest:[NSString stringWithFormat:@"grant_type=authorization_code&code=%@&redirect_uri=%@&client_id=%@&code_verifier=%@",
                              formEnc(code),formEnc(redirect),formEnc(ss.clientID),verifier] done:done];
        });
    }];
    self.webAuth.presentationContextProvider=self;
    self.webAuth.prefersEphemeralWebBrowserSession=NO;
    if (![self.webAuth start]) { self.webAuth=nil; done(nil,@"Couldn't open the Spotify login."); }
}

- (void)connectWithToken {
    [self withToken:^(NSString *tok, NSString *err) {
        if (!tok) { [self finish:NO error:err]; return; }
        self.remote.connectionParameters.accessToken=tok;
        [self.remote connect];
    }];
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
    self.authorizing=NO; self.triedAppAuthorize=NO;
    appRemote.playerAPI.delegate=self;
    [appRemote.playerAPI subscribeToPlayerState:nil];
    [self playPending];
}
- (void)appRemote:(SPTAppRemote *)appRemote didFailConnectionAttemptWithError:(NSError *)error {
    if (!self.pendingURI) return;
    // Usually the Spotify app isn't running. Wake it once through the SDK (it starts the song and comes back);
    // if that doesn't work either, ask the user to open Spotify once.
    if (!self.triedAppAuthorize) { self.triedAppAuthorize=YES; self.authorizing=NO; [self authorize]; return; }
    [self finish:NO error:@"Couldn't reach the Spotify app.\n\nOpen Spotify, play any song for a second, then come back to Spofity and tap the song again."];
    self.pendingURI=nil;
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
        [[NSUserDefaults standardUserDefaults] setDouble:[NSDate timeIntervalSinceReferenceDate]+3300 forKey:kExpiryKey];
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
    if (!m.webAuth) m.authorizing=NO;   // came back from Spotify without an answer: allow a new attempt
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
    else { m.triedAppAuthorize=NO; [m connectWithToken]; }   // in-app login if needed, then connect
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
