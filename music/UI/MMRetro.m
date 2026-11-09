// MMRetro.m - draws the iOS 6 controls spofity was designed around, for modern iOS builds (MM_MODERN).
#import "MMRetro.h"

#ifdef MM_MODERN
#import <objc/runtime.h>
#import <objc/message.h>

#define MMRetroStatusH 20.0

#pragma mark - Drawing helpers

static void rgbOf(UIColor *c, CGFloat *r, CGFloat *g, CGFloat *b) {
    CGFloat a=1, w=0;
    if (![c getRed:r green:g blue:b alpha:&a]) {
        if ([c getWhite:&w alpha:&a]) { *r=*g=*b=w; } else { *r=*g=*b=0.5; }
    }
}
static UIColor *shade(UIColor *c, CGFloat d) {
    CGFloat r,g,b; rgbOf(c,&r,&g,&b);
    return [UIColor colorWithRed:MAX(0,MIN(1,r+d)) green:MAX(0,MIN(1,g+d)) blue:MAX(0,MIN(1,b+d)) alpha:1];
}
static UIColor *gray(CGFloat w) { return [UIColor colorWithWhite:w alpha:1]; }

// Vertical gradient inside the current context's clip.
static void fillGradient(CGContextRef ctx, CGRect r, NSArray *colors, const CGFloat *locs) {
    NSMutableArray *cg=[NSMutableArray array];
    for (UIColor *c in colors) [cg addObject:(id)c.CGColor];
    CGColorSpaceRef rgb=CGColorSpaceCreateDeviceRGB();
    CGGradientRef g=CGGradientCreateWithColors(rgb,(__bridge CFArrayRef)cg,locs);
    CGContextDrawLinearGradient(ctx,g,CGPointMake(0,CGRectGetMinY(r)),CGPointMake(0,CGRectGetMaxY(r)),0);
    CGGradientRelease(g); CGColorSpaceRelease(rgb);
}

static UIImage *drawImage(CGSize s, void (^draw)(CGContextRef ctx)) {
    UIGraphicsImageRendererFormat *f=[UIGraphicsImageRendererFormat preferredFormat]; f.opaque=NO;
    UIGraphicsImageRenderer *r=[[UIGraphicsImageRenderer alloc] initWithSize:s format:f];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *rc){ draw(rc.CGContext); }];
}

static UIFont *helv(CGFloat s, BOOL bold) {
    return [UIFont fontWithName:(bold?@"Helvetica-Bold":@"Helvetica") size:s] ?: (bold?[UIFont boldSystemFontOfSize:s]:[UIFont systemFontOfSize:s]);
}
static NSShadow *textShadow(UIColor *c, CGFloat dy) {
    NSShadow *s=[NSShadow new]; s.shadowColor=c; s.shadowOffset=CGSizeMake(0,dy); s.shadowBlurRadius=0; return s;
}

// iOS 6 bar: glossy gradient, light line on top, dark line at the bottom.
static UIImage *barImage(UIColor *tint, CGFloat h) {
    return drawImage(CGSizeMake(8,h), ^(CGContextRef ctx){
        CGRect r=CGRectMake(0,0,8,h);
        if (tint) {
            CGFloat locs[]={0,0.5,0.5,1};
            fillGradient(ctx,r,@[shade(tint,0.16),shade(tint,0.07),shade(tint,0.03),shade(tint,-0.04)],locs);
            [shade(tint,0.30) setFill]; UIRectFill(CGRectMake(0,0,8,1));
            [shade(tint,-0.22) setFill]; UIRectFill(CGRectMake(0,h-1,8,1));
        } else {
            CGFloat locs[]={0,0.5,0.5,1};
            fillGradient(ctx,r,@[gray(0.30),gray(0.17),gray(0.09),gray(0.02)],locs);
            [gray(0.40) setFill]; UIRectFill(CGRectMake(0,0,8,1));
            [gray(0.0) setFill]; UIRectFill(CGRectMake(0,h-1,8,1));
        }
    });
}

UIImage *MMRetroGlossImage(UIColor *base, CGSize size, CGFloat radius, BOOL pressed) {
    UIImage *img=drawImage(size, ^(CGContextRef ctx){
        CGRect outer=CGRectMake(0,0,size.width,size.height-1);
        // 1 px light shadow under the button (iOS 6 "engraved" look)
        [[UIColor colorWithWhite:1 alpha:0.18] setFill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectOffset(outer,0,1) cornerRadius:radius] fill];
        // dark border
        [shade(base,-0.28) setFill];
        [[UIBezierPath bezierPathWithRoundedRect:outer cornerRadius:radius] fill];
        // body
        CGRect inner=CGRectInset(outer,1,1);
        CGContextSaveGState(ctx);
        [[UIBezierPath bezierPathWithRoundedRect:inner cornerRadius:MAX(0,radius-1)] addClip];
        if (pressed) {
            CGFloat locs[]={0,1}; fillGradient(ctx,inner,@[shade(base,-0.14),shade(base,-0.05)],locs);
        } else {
            CGFloat locs[]={0,0.5,0.5,1};
            fillGradient(ctx,inner,@[shade(base,0.20),shade(base,0.08),shade(base,0.02),shade(base,-0.05)],locs);
            [[UIColor colorWithWhite:1 alpha:0.28] setFill]; UIRectFill(CGRectMake(inner.origin.x,inner.origin.y,inner.size.width,1));
        }
        CGContextRestoreGState(ctx);
    });
    CGFloat c=radius+2;
    return [img resizableImageWithCapInsets:UIEdgeInsetsMake(c,c,c,c) resizingMode:UIImageResizingModeStretch];
}

static UIColor *doneBlue(void) { return [UIColor colorWithRed:0.16 green:0.40 blue:0.90 alpha:1]; }
static UIColor *buttonBase(UIColor *tint) { return tint ? shade(tint,-0.06) : gray(0.16); }

#pragma mark - Fonts and screen

@implementation UIFont (MMRetro)
+ (UIFont *)mm_systemFontOfSize:(CGFloat)s { return [UIFont fontWithName:@"Helvetica" size:s] ?: [self mm_systemFontOfSize:s]; }
+ (UIFont *)mm_boldSystemFontOfSize:(CGFloat)s { return [UIFont fontWithName:@"Helvetica-Bold" size:s] ?: [self mm_boldSystemFontOfSize:s]; }
+ (UIFont *)mm_italicSystemFontOfSize:(CGFloat)s { return [UIFont fontWithName:@"Helvetica-Oblique" size:s] ?: [self mm_italicSystemFontOfSize:s]; }
@end

@implementation UIScreen (MMRetro)
// iOS 6 semantics: everything below the 20 pt status bar. (Deprecated on modern iOS and no longer reliable.)
- (CGRect)mm_applicationFrame { CGRect b=self.bounds; return CGRectMake(0,MMRetroStatusH,b.size.width,b.size.height-MMRetroStatusH); }
@end

// iOS 14+: a UIToolbar puts its own content view over everything added with addSubview:, which hides and blocks
// spofity's mini player (cover, title, play button). After each layout, move our own subviews back on top, keeping their order.
@implementation UIToolbar (MMRetro)
- (void)mm_layoutSubviews {
    [self mm_layoutSubviews];
    for (UIView *v in [self.subviews copy])
        if (![NSStringFromClass([v class]) hasPrefix:@"_"]) [self bringSubviewToFront:v];
}
@end

// iOS 6 table selection: blue (default) or gray gradient instead of the flat modern highlight.
static UIView *selectionView(BOOL isGray) {
    static UIImage *blue, *grayImg;
    if (!blue) {
        blue=drawImage(CGSizeMake(4,44), ^(CGContextRef ctx){ CGFloat l[]={0,1};
            fillGradient(ctx,CGRectMake(0,0,4,44),@[[UIColor colorWithRed:0.02 green:0.55 blue:0.96 alpha:1],[UIColor colorWithRed:0.0 green:0.36 blue:0.88 alpha:1]],l); });
        grayImg=drawImage(CGSizeMake(4,44), ^(CGContextRef ctx){ CGFloat l[]={0,1};
            fillGradient(ctx,CGRectMake(0,0,4,44),@[gray(0.75),gray(0.58)],l); });
    }
    UIImageView *v=[[UIImageView alloc] initWithImage:isGray?grayImg:blue];
    v.contentMode=UIViewContentModeScaleToFill; v.tag=0x6006;   // marks our own view (an app-set one is left alone)
    return v;
}
@implementation UITableViewCell (MMRetro)
- (instancetype)mm_initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid {
    UITableViewCell *c=[self mm_initWithStyle:style reuseIdentifier:rid];
    if (c) { c.selectedBackgroundView=selectionView(NO); c.textLabel.highlightedTextColor=[UIColor whiteColor]; c.detailTextLabel.highlightedTextColor=[UIColor whiteColor]; }
    return c;
}
- (void)mm_setSelectionStyle:(UITableViewCellSelectionStyle)st {
    [self mm_setSelectionStyle:st];
    if (self.selectedBackgroundView && self.selectedBackgroundView.tag!=0x6006) return;
    if (st==UITableViewCellSelectionStyleGray) self.selectedBackgroundView=selectionView(YES);
    else if (st==UITableViewCellSelectionStyleBlue || st==UITableViewCellSelectionStyleDefault) self.selectedBackgroundView=selectionView(NO);
}
@end

static void swapClass(Class c, SEL a, SEL b) {
    Method m1=class_getClassMethod(c,a), m2=class_getClassMethod(c,b);
    if (m1 && m2) method_exchangeImplementations(m1,m2);
}
static void swapInstance(Class c, SEL a, SEL b) {
    Method m1=class_getInstanceMethod(c,a), m2=class_getInstanceMethod(c,b);
    if (m1 && m2) method_exchangeImplementations(m1,m2);
}

#pragma mark - Status bar strip

static UIWindow *gStatusWin;
static UIImageView *gStatusImg;
static BOOL gStatusDark=YES, gStatusHidden=NO;

static void updateStatusStrip(void) {
    if (!gStatusWin) {
        CGRect b=[UIScreen mainScreen].bounds;
        gStatusWin=[[UIWindow alloc] initWithFrame:CGRectMake(0,0,b.size.width,MMRetroStatusH)];
        gStatusWin.windowLevel=UIWindowLevelNormal+1;
        gStatusWin.userInteractionEnabled=NO;
        gStatusWin.backgroundColor=[UIColor clearColor];
        // Every window needs a root view controller at the end of launch, or UIKit aborts the app.
        UIViewController *vc=[UIViewController new];
        vc.view.backgroundColor=[UIColor clearColor]; vc.view.userInteractionEnabled=NO;
        gStatusWin.rootViewController=vc;
        gStatusImg=[[UIImageView alloc] initWithFrame:vc.view.bounds];
        gStatusImg.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        gStatusImg.contentMode=UIViewContentModeScaleToFill;
        [vc.view addSubview:gStatusImg];
    }
    if (gStatusDark) gStatusImg.image=drawImage(CGSizeMake(4,MMRetroStatusH), ^(CGContextRef ctx){ [gray(0) setFill]; UIRectFill(CGRectMake(0,0,4,MMRetroStatusH)); });
    else gStatusImg.image=drawImage(CGSizeMake(4,MMRetroStatusH), ^(CGContextRef ctx){
        CGFloat locs[]={0,1}; fillGradient(ctx,CGRectMake(0,0,4,MMRetroStatusH),@[gray(0.93),gray(0.72)],locs);
        [gray(0.45) setFill]; UIRectFill(CGRectMake(0,MMRetroStatusH-1,4,1));
    });
    gStatusWin.hidden=gStatusHidden;
}

void MMStatusBarDark(BOOL dark) {
    gStatusDark=dark;
    UIStatusBarStyle st=dark?UIStatusBarStyleLightContent:UIStatusBarStyleDarkContent;
    [[UIApplication sharedApplication] setStatusBarStyle:st animated:NO];
    updateStatusStrip();
}
void MMStatusBarHidden(BOOL hidden) {
    gStatusHidden=hidden;
    [[UIApplication sharedApplication] setStatusBarHidden:hidden withAnimation:UIStatusBarAnimationFade];
    updateStatusStrip();
}

#pragma mark - Modal presentation below the status bar

// iOS 6 put full-screen modals (player, queue, sheets) below the 20 pt status bar. Modern iOS presents them as cards,
// or full screen under the status bar. A custom presentation gives back the iOS 6 frame; the animation stays the
// standard slide-up because no animator is supplied.
@interface MMRetroPresentation : UIPresentationController
@end
@implementation MMRetroPresentation
- (CGRect)frameOfPresentedViewInContainerView {
    CGRect b=self.containerView.bounds;
    return CGRectMake(0,MMRetroStatusH,b.size.width,b.size.height-MMRetroStatusH);
}
- (BOOL)shouldRemovePresentersView { return NO; }
- (void)containerViewWillLayoutSubviews { self.presentedView.frame=[self frameOfPresentedViewInContainerView]; }
@end
@interface MMRetroModalDelegate : NSObject <UIViewControllerTransitioningDelegate>
@end
@implementation MMRetroModalDelegate
- (UIPresentationController *)presentationControllerForPresentedViewController:(UIViewController *)presented
                                                      presentingViewController:(UIViewController *)presenting sourceViewController:(UIViewController *)source {
    return [[MMRetroPresentation alloc] initWithPresentedViewController:presented presentingViewController:presenting];
}
@end

@implementation UIViewController (MMRetro)
- (void)mm_presentViewController:(UIViewController *)vc animated:(BOOL)animated completion:(void (^)(void))completion {
    static MMRetroModalDelegate *del; if (!del) del=[MMRetroModalDelegate new];
    BOOL phone=([UIDevice currentDevice].userInterfaceIdiom==UIUserInterfaceIdiomPhone);
    UIModalPresentationStyle st=vc.modalPresentationStyle;
    BOOL ours=[NSStringFromClass([vc class]) hasPrefix:@"MM"] || [vc isKindOfClass:[UINavigationController class]];
    if (ours && (phone || st==UIModalPresentationFullScreen) && st!=UIModalPresentationFormSheet && st!=UIModalPresentationPopover) {
        vc.modalPresentationStyle=UIModalPresentationCustom;
        vc.transitioningDelegate=del;
    }
    [self mm_presentViewController:vc animated:animated completion:completion];
}
@end

// Root view controllers built for iOS 6 (login) expect their view to start below the status bar.
@interface MMRetroStatusContainer : UIViewController
@property (nonatomic, strong) UIViewController *inner;
@end
@implementation MMRetroStatusContainer
- (void)loadView {
    self.view=[[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.view.backgroundColor=[UIColor blackColor];
    [self addChildViewController:self.inner];
    UIView *v=self.inner.view;
    v.frame=CGRectMake(0,MMRetroStatusH,self.view.bounds.size.width,self.view.bounds.size.height-MMRetroStatusH);
    v.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:v];
    [self.inner didMoveToParentViewController:self];
}
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return self.inner.supportedInterfaceOrientations; }
@end

UIViewController *MMRetroBelowStatusBar(UIViewController *vc) {
    MMRetroStatusContainer *c=[MMRetroStatusContainer new]; c.inner=vc; return c;
}
UIViewController *MMRetroUnwrap(UIViewController *vc) {
    return [vc isKindOfClass:[MMRetroStatusContainer class]] ? ((MMRetroStatusContainer *)vc).inner : vc;
}

#pragma mark - Install

void MMRetroInstall(void) {
    static BOOL done=NO; if (done) return; done=YES;
    swapClass([UIFont class],@selector(systemFontOfSize:),@selector(mm_systemFontOfSize:));
    swapClass([UIFont class],@selector(boldSystemFontOfSize:),@selector(mm_boldSystemFontOfSize:));
    swapClass([UIFont class],@selector(italicSystemFontOfSize:),@selector(mm_italicSystemFontOfSize:));
    swapInstance([UIScreen class],@selector(applicationFrame),@selector(mm_applicationFrame));
    swapInstance([UIViewController class],@selector(presentViewController:animated:completion:),@selector(mm_presentViewController:animated:completion:));
    swapInstance([UIToolbar class],@selector(layoutSubviews),@selector(mm_layoutSubviews));
    swapInstance([UITableViewCell class],@selector(initWithStyle:reuseIdentifier:),@selector(mm_initWithStyle:reuseIdentifier:));
    swapInstance([UITableViewCell class],@selector(setSelectionStyle:),@selector(mm_setSelectionStyle:));

    // Defaults for bars spofity doesn't style itself (e.g. the sheet's navigation controller).
    UINavigationBarAppearance *nav=[UINavigationBarAppearance new];
    [nav configureWithOpaqueBackground];
    nav.backgroundImage=barImage(nil,44); nav.backgroundImageContentMode=UIViewContentModeScaleToFill;
    nav.shadowColor=nil; nav.shadowImage=nil;
    nav.titleTextAttributes=@{NSFontAttributeName:helv(20,YES), NSForegroundColorAttributeName:[UIColor whiteColor],
                              NSShadowAttributeName:textShadow([UIColor colorWithWhite:0 alpha:0.5],-1)};
    [UINavigationBar appearance].standardAppearance=nav;
    [UINavigationBar appearance].compactAppearance=nav;
    [UINavigationBar appearance].scrollEdgeAppearance=nav;
    [UINavigationBar appearance].tintColor=[UIColor whiteColor];
    [UIToolbar appearance].tintColor=[UIColor whiteColor];
    updateStatusStrip();
}

#pragma mark - Bars

void MMRetroStyleNavBar(UINavigationBar *bar, UIColor *tint, UIImage *texture) {
    if (!bar) return;
    UINavigationBarAppearance *a=[UINavigationBarAppearance new];
    [a configureWithOpaqueBackground];
    a.backgroundColor=tint?:[UIColor blackColor];
    UIImage *bg=barImage(tint,44);
    if (texture) {   // dark mode stripe: texture with the bar's top/bottom lines
        bg=drawImage(CGSizeMake(8,44), ^(CGContextRef ctx){
            [texture drawInRect:CGRectMake(0,0,8,44)];
            [gray(0.40) setFill]; UIRectFill(CGRectMake(0,0,8,1));
            [gray(0.0) setFill]; UIRectFill(CGRectMake(0,43,8,1));
        });
    }
    a.backgroundImage=bg; a.backgroundImageContentMode=UIViewContentModeScaleToFill;
    a.shadowColor=nil; a.shadowImage=nil;
    a.titleTextAttributes=@{NSFontAttributeName:helv(20,YES), NSForegroundColorAttributeName:[UIColor whiteColor],
                            NSShadowAttributeName:textShadow([UIColor colorWithWhite:0 alpha:0.5],-1)};
    bar.standardAppearance=a; bar.compactAppearance=a; bar.scrollEdgeAppearance=a;
    if (@available(iOS 15.0, *)) bar.compactScrollEdgeAppearance=a;
    bar.tintColor=[UIColor whiteColor];
    bar.translucent=NO;
    MMRetroRetintItems(bar.topItem, tint);
}

void MMRetroStyleToolbar(UIToolbar *bar, BOOL dark) {
    if (!bar) return;
    UIToolbarAppearance *a=[UIToolbarAppearance new];
    [a configureWithOpaqueBackground];
    CGFloat h=MAX(24,bar.bounds.size.height);
    UIImage *bg;
    if (dark) bg=barImage(nil,h);
    else bg=drawImage(CGSizeMake(8,h), ^(CGContextRef ctx){
        CGFloat locs[]={0,0.5,0.5,1};
        fillGradient(ctx,CGRectMake(0,0,8,h),@[gray(0.66),gray(0.57),gray(0.52),gray(0.44)],locs);
        [gray(0.78) setFill]; UIRectFill(CGRectMake(0,0,8,1));
        [gray(0.30) setFill]; UIRectFill(CGRectMake(0,h-1,8,1));
    });
    a.backgroundImage=bg; a.backgroundImageContentMode=UIViewContentModeScaleToFill;
    a.backgroundColor=dark?[UIColor blackColor]:gray(0.55);
    a.shadowColor=nil; a.shadowImage=nil;
    bar.standardAppearance=a; bar.compactAppearance=a;
    if (@available(iOS 15.0, *)) { bar.scrollEdgeAppearance=a; bar.compactScrollEdgeAppearance=a; }
    bar.tintColor=[UIColor whiteColor];
    bar.translucent=NO;
}

void MMRetroToolbarBackground(UIToolbar *bar, UIImage *image) {
    if (!bar || !image) return;
    UIToolbarAppearance *a=[UIToolbarAppearance new];
    [a configureWithOpaqueBackground];
    a.backgroundImage=image; a.backgroundImageContentMode=UIViewContentModeScaleToFill;
    a.shadowColor=nil; a.shadowImage=nil;
    bar.standardAppearance=a; bar.compactAppearance=a;
    if (@available(iOS 15.0, *)) { bar.scrollEdgeAppearance=a; bar.compactScrollEdgeAppearance=a; }
}

void MMRetroStyleTabBar(UITabBar *bar, UIColor *accent) {
    if (!bar) return;
    CGFloat h=49;
    UIImage *bg=drawImage(CGSizeMake(8,h), ^(CGContextRef ctx){
        CGFloat locs[]={0,0.5,0.5,1};
        fillGradient(ctx,CGRectMake(0,0,8,h),@[gray(0.22),gray(0.13),gray(0.05),gray(0.0)],locs);
        [gray(0.32) setFill]; UIRectFill(CGRectMake(0,0,8,1));
    });
    UIImage *sel=drawImage(CGSizeMake(24,h), ^(CGContextRef ctx){
        UIBezierPath *p=[UIBezierPath bezierPathWithRoundedRect:CGRectMake(2,2,20,h-4) cornerRadius:4];
        [[UIColor colorWithWhite:1 alpha:0.13] setFill]; [p fill];
        CGContextSaveGState(ctx); [p addClip];
        [[UIColor colorWithWhite:1 alpha:0.07] setFill]; UIRectFill(CGRectMake(2,2,20,(h-4)/2));
        CGContextRestoreGState(ctx);
    });
    sel=[sel resizableImageWithCapInsets:UIEdgeInsetsMake(8,8,8,8) resizingMode:UIImageResizingModeStretch];
    UITabBarAppearance *a=[UITabBarAppearance new];
    [a configureWithOpaqueBackground];
    a.backgroundColor=[UIColor blackColor];
    a.backgroundImage=bg; a.backgroundImageContentMode=UIViewContentModeScaleToFill;
    a.shadowColor=nil; a.shadowImage=nil;
    a.selectionIndicatorImage=sel;
    UIColor *dim=gray(0.58);
    for (UITabBarItemAppearance *ia in @[a.stackedLayoutAppearance,a.inlineLayoutAppearance,a.compactInlineLayoutAppearance]) {
        ia.normal.iconColor=dim;
        ia.normal.titleTextAttributes=@{NSFontAttributeName:helv(10,YES), NSForegroundColorAttributeName:dim};
        ia.selected.iconColor=accent?:doneBlue();
        ia.selected.titleTextAttributes=@{NSFontAttributeName:helv(10,YES), NSForegroundColorAttributeName:[UIColor whiteColor]};
    }
    bar.standardAppearance=a;
    if (@available(iOS 15.0, *)) bar.scrollEdgeAppearance=a;
    bar.translucent=NO;
    bar.itemPositioning=UITabBarItemPositioningFill;
}

void MMRetroStyleSearchBar(UISearchBar *bar, BOOL dark) {
    if (!bar) return;
    UIImage *field=drawImage(CGSizeMake(31,31), ^(CGContextRef ctx){
        CGRect r=CGRectMake(0.5,0.5,30,30);
        UIBezierPath *p=[UIBezierPath bezierPathWithRoundedRect:r cornerRadius:15];
        [[UIColor whiteColor] setFill]; [p fill];
        CGContextSaveGState(ctx); [p addClip];   // inner shadow at the top
        CGFloat locs[]={0,1}; fillGradient(ctx,CGRectMake(0,0,31,6),@[[UIColor colorWithWhite:0 alpha:0.18],[UIColor colorWithWhite:0 alpha:0]],locs);
        CGContextRestoreGState(ctx);
        [gray(dark?0.15:0.62) setStroke]; p.lineWidth=1; [p stroke];
    });
    [bar setSearchFieldBackgroundImage:[field resizableImageWithCapInsets:UIEdgeInsetsMake(15,15,15,15)] forState:UIControlStateNormal];
    bar.searchTextField.font=helv(15,NO);
    bar.searchTextField.textColor=[UIColor blackColor];
    bar.searchTextField.backgroundColor=[UIColor clearColor];
    bar.searchTextPositionAdjustment=UIOffsetMake(2,0);
    if (dark) bar.backgroundImage=barImage(gray(0.30),44);
}

static UIImage *sliderTrack(UIColor *fill, BOOL light) {
    UIImage *img=drawImage(CGSizeMake(13,11), ^(CGContextRef ctx){
        CGRect r=CGRectMake(0.5,1.5,12,9);
        UIBezierPath *p=[UIBezierPath bezierPathWithRoundedRect:r cornerRadius:4.5];
        CGContextSaveGState(ctx); [p addClip];
        CGFloat locs[]={0,1};
        if (light) fillGradient(ctx,r,@[gray(0.86),gray(1.0)],locs);
        else fillGradient(ctx,r,@[shade(fill,-0.12),shade(fill,0.12)],locs);
        CGContextRestoreGState(ctx);
        [[UIColor colorWithWhite:0 alpha:0.45] setStroke]; p.lineWidth=1; [p stroke];
    });
    return [img resizableImageWithCapInsets:UIEdgeInsetsMake(0,6,0,6) resizingMode:UIImageResizingModeStretch];
}
static UIImage *sliderThumb(BOOL pressed) {
    return drawImage(CGSizeMake(25,25), ^(CGContextRef ctx){
        CGRect r=CGRectMake(1.5,1,22,22);
        CGContextSetShadowWithColor(ctx,CGSizeMake(0,1),1.5,[UIColor colorWithWhite:0 alpha:0.5].CGColor);
        [gray(0.55) setFill]; [[UIBezierPath bezierPathWithOvalInRect:r] fill];
        CGContextSetShadowWithColor(ctx,CGSizeZero,0,NULL);
        UIBezierPath *in=[UIBezierPath bezierPathWithOvalInRect:CGRectInset(r,0.5,0.5)];
        CGContextSaveGState(ctx); [in addClip];
        CGFloat locs[]={0,1};
        fillGradient(ctx,r,pressed?@[gray(0.80),gray(0.95)]:@[gray(1.0),gray(0.80)],locs);
        CGContextRestoreGState(ctx);
    });
}

void MMRetroStyleSlider(UISlider *slider, UIColor *accent) {
    if (!slider) return;
    [slider setThumbImage:sliderThumb(NO) forState:UIControlStateNormal];
    [slider setThumbImage:sliderThumb(YES) forState:UIControlStateHighlighted];
    [slider setMinimumTrackImage:sliderTrack(accent?:doneBlue(),NO) forState:UIControlStateNormal];
    [slider setMaximumTrackImage:sliderTrack(nil,YES) forState:UIControlStateNormal];
}

void MMRetroStyleVolumeView(id v, UIColor *accent) {
    if (!v) return;
    SEL thumb=NSSelectorFromString(@"setVolumeThumbImage:forState:");
    SEL mn=NSSelectorFromString(@"setMinimumVolumeSliderImage:forState:");
    SEL mx=NSSelectorFromString(@"setMaximumVolumeSliderImage:forState:");
    void (*send)(id,SEL,id,NSUInteger)=(void(*)(id,SEL,id,NSUInteger))objc_msgSend;
    if ([v respondsToSelector:thumb]) { send(v,thumb,sliderThumb(NO),UIControlStateNormal); send(v,thumb,sliderThumb(YES),UIControlStateHighlighted); }
    if ([v respondsToSelector:mn]) send(v,mn,sliderTrack(accent?:doneBlue(),NO),UIControlStateNormal);
    if ([v respondsToSelector:mx]) send(v,mx,sliderTrack(nil,YES),UIControlStateNormal);
}

void MMRetroStyleRoundedRectButton(UIButton *b) {
    if (!b) return;
    UIImage *n=drawImage(CGSizeMake(21,21), ^(CGContextRef ctx){
        UIBezierPath *p=[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0.5,0.5,20,20) cornerRadius:9];
        CGContextSaveGState(ctx); [p addClip];
        CGFloat locs[]={0,1}; fillGradient(ctx,CGRectMake(0,0,21,21),@[gray(1.0),gray(0.94)],locs);
        CGContextRestoreGState(ctx);
        [gray(0.60) setStroke]; p.lineWidth=1; [p stroke];
    });
    UIImage *h=drawImage(CGSizeMake(21,21), ^(CGContextRef ctx){
        UIBezierPath *p=[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0.5,0.5,20,20) cornerRadius:9];
        CGContextSaveGState(ctx); [p addClip];
        CGFloat locs[]={0,1}; fillGradient(ctx,CGRectMake(0,0,21,21),@[[UIColor colorWithRed:0.02 green:0.55 blue:0.96 alpha:1],[UIColor colorWithRed:0.0 green:0.36 blue:0.88 alpha:1]],locs);
        CGContextRestoreGState(ctx);
        [gray(0.40) setStroke]; p.lineWidth=1; [p stroke];
    });
    UIEdgeInsets c=UIEdgeInsetsMake(10,10,10,10);
    [b setBackgroundImage:[n resizableImageWithCapInsets:c] forState:UIControlStateNormal];
    [b setBackgroundImage:[h resizableImageWithCapInsets:c] forState:UIControlStateHighlighted];
    if (![b titleColorForState:UIControlStateNormal] || [[b titleColorForState:UIControlStateNormal] isEqual:b.tintColor])
        [b setTitleColor:[UIColor colorWithRed:0.20 green:0.31 blue:0.52 alpha:1] forState:UIControlStateNormal];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateHighlighted];
}

void MMRetroStyleGroupedTable(UITableView *t) {
    if (!t) return;
    if (@available(iOS 15.0, *)) t.sectionHeaderTopPadding=0;
    t.preservesSuperviewLayoutMargins=NO;
    t.insetsLayoutMarginsFromSafeArea=NO;
    t.cellLayoutMarginsFollowReadableWidth=NO;
    t.layoutMargins=UIEdgeInsetsMake(0,10,0,10);   // iOS 6: sections 10 pt from the edges
}

UIImage *MMRetroPlusImage(void) {
    return drawImage(CGSizeMake(16,17), ^(CGContextRef ctx){
        CGContextSetShadowWithColor(ctx,CGSizeMake(0,-1),0,[UIColor colorWithWhite:0 alpha:0.5].CGColor);
        [[UIColor whiteColor] setFill];
        UIRectFill(CGRectMake(6.5,2,3,13)); UIRectFill(CGRectMake(1.5,7,13,3));
    });
}

#pragma mark - Bar buttons

@interface MMRetroBarButton : UIButton
@property (nonatomic) BOOL done;
@end
@implementation MMRetroBarButton
- (void)retint:(UIColor *)tint {
    UIColor *base=self.done?doneBlue():buttonBase(tint);
    [self setBackgroundImage:MMRetroGlossImage(base,CGSizeMake(13,31),5,NO) forState:UIControlStateNormal];
    [self setBackgroundImage:MMRetroGlossImage(base,CGSizeMake(13,31),5,YES) forState:UIControlStateHighlighted];
}
@end

UIBarButtonItem *MMRetroBarItem(NSString *title, UIImage *image, BOOL done, UIColor *tint, id target, SEL action) {
    MMRetroBarButton *b=[MMRetroBarButton buttonWithType:UIButtonTypeCustom];
    b.done=done;
    [b retint:tint];
    CGFloat w=40;
    if (title) {
        [b setTitle:title forState:UIControlStateNormal];
        b.titleLabel.font=helv(12,YES);
        b.titleLabel.shadowOffset=CGSizeMake(0,-1);
        [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [b setTitleShadowColor:[UIColor colorWithWhite:0 alpha:0.5] forState:UIControlStateNormal];
        w=MAX(48,ceil([title sizeWithAttributes:@{NSFontAttributeName:b.titleLabel.font}].width)+22);
    }
    if (image) {
        [b setImage:[image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forState:UIControlStateNormal];
        w=MAX(w,image.size.width+20);
    }
    b.frame=CGRectMake(0,0,w,31);
    [b.widthAnchor constraintEqualToConstant:w].active=YES;
    [b.heightAnchor constraintEqualToConstant:31].active=YES;
    if (target && action) [b addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return [[UIBarButtonItem alloc] initWithCustomView:b];
}

void MMRetroRetintItems(UINavigationItem *item, UIColor *tint) {
    if (!item) return;
    NSMutableArray *all=[NSMutableArray array];
    if (item.leftBarButtonItems) [all addObjectsFromArray:item.leftBarButtonItems];
    if (item.rightBarButtonItems) [all addObjectsFromArray:item.rightBarButtonItems];
    for (UIBarButtonItem *i in all) if ([i.customView isKindOfClass:[MMRetroBarButton class]]) [(MMRetroBarButton *)i.customView retint:tint];
}

#pragma mark - Switch

@implementation MMRetroSwitch {
    UIView *_clip; UIImageView *_strip; UIImageView *_frameImg;
}
static const CGFloat kSwW=79, kSwH=27, kKnob=27;

- (instancetype)initWithFrame:(CGRect)frame {
    self=[super initWithFrame:CGRectMake(frame.origin.x,frame.origin.y,kSwW,kSwH)];
    if (self) {
        _onTintColor=[UIColor colorWithRed:0.0 green:0.50 blue:0.92 alpha:1];
        _clip=[[UIView alloc] initWithFrame:self.bounds]; _clip.userInteractionEnabled=NO;
        _clip.layer.cornerRadius=kSwH/2; _clip.clipsToBounds=YES;
        [self addSubview:_clip];
        _strip=[[UIImageView alloc] initWithFrame:CGRectMake(0,0,kSwW*2-kKnob,kSwH)];
        [_clip addSubview:_strip];
        _frameImg=[[UIImageView alloc] initWithFrame:self.bounds]; _frameImg.userInteractionEnabled=NO;
        [self addSubview:_frameImg];
        [self redraw];
        [self place:NO];
        [self addTarget:self action:@selector(tapped) forControlEvents:UIControlEventTouchUpInside];
    }
    return self;
}
- (instancetype)init { return [self initWithFrame:CGRectZero]; }
- (void)setFrame:(CGRect)frame { frame.size=CGSizeMake(kSwW,kSwH); [super setFrame:frame]; }
- (CGSize)sizeThatFits:(CGSize)size { return CGSizeMake(kSwW,kSwH); }
- (CGSize)intrinsicContentSize { return CGSizeMake(kSwW,kSwH); }
- (void)setOnTintColor:(UIColor *)c { _onTintColor=c?:[UIColor colorWithRed:0.0 green:0.50 blue:0.92 alpha:1]; [self redraw]; }
- (void)redraw {
    CGFloat side=kSwW-kKnob/2;   // visible width of the ON / OFF halves next to the knob
    UIColor *on=_onTintColor;
    _strip.image=drawImage(_strip.bounds.size, ^(CGContextRef ctx){
        CGFloat W=kSwW*2-kKnob, H=kSwH, locs[]={0,1};
        CGContextSaveGState(ctx); CGContextClipToRect(ctx,CGRectMake(0,0,side,H));
        fillGradient(ctx,CGRectMake(0,0,W,H),@[shade(on,-0.10),shade(on,0.10)],locs);
        CGContextRestoreGState(ctx);
        CGContextSaveGState(ctx); CGContextClipToRect(ctx,CGRectMake(side,0,W-side,H));
        fillGradient(ctx,CGRectMake(0,0,W,H),@[gray(0.86),gray(0.99)],locs);
        CGContextRestoreGState(ctx);
        NSDictionary *onA=@{NSFontAttributeName:helv(16,YES), NSForegroundColorAttributeName:[UIColor whiteColor], NSShadowAttributeName:textShadow([UIColor colorWithWhite:0 alpha:0.35],-1)};
        NSDictionary *offA=@{NSFontAttributeName:helv(16,YES), NSForegroundColorAttributeName:gray(0.50)};
        CGSize s1=[@"ON" sizeWithAttributes:onA], s2=[@"OFF" sizeWithAttributes:offA];
        CGFloat onMid=(kSwW-kKnob)/2, offMid=kSwW+(kSwW-kKnob)/2-kKnob/2+kKnob/2;
        [@"ON" drawAtPoint:CGPointMake(onMid-s1.width/2,(H-s1.height)/2) withAttributes:onA];
        [@"OFF" drawAtPoint:CGPointMake(offMid-s2.width/2,(H-s2.height)/2) withAttributes:offA];
        // knob
        CGRect k=CGRectMake(kSwW-kKnob,0,kKnob,kKnob);
        CGContextSetShadowWithColor(ctx,CGSizeZero,2,[UIColor colorWithWhite:0 alpha:0.5].CGColor);
        [gray(0.62) setFill]; [[UIBezierPath bezierPathWithOvalInRect:CGRectInset(k,0.5,0.5)] fill];
        CGContextSetShadowWithColor(ctx,CGSizeZero,0,NULL);
        UIBezierPath *kp=[UIBezierPath bezierPathWithOvalInRect:CGRectInset(k,1,1)];
        CGContextSaveGState(ctx); [kp addClip]; fillGradient(ctx,k,@[gray(0.82),gray(1.0)],locs); CGContextRestoreGState(ctx);
    });
    _frameImg.image=drawImage(self.bounds.size, ^(CGContextRef ctx){
        UIBezierPath *p=[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0.5,0.5,kSwW-1,kSwH-1) cornerRadius:(kSwH-1)/2];
        CGContextSaveGState(ctx); [p addClip];   // inner shadow
        CGFloat locs[]={0,1}; fillGradient(ctx,CGRectMake(0,0,kSwW,7),@[[UIColor colorWithWhite:0 alpha:0.30],[UIColor colorWithWhite:0 alpha:0]],locs);
        CGContextRestoreGState(ctx);
        [[UIColor colorWithWhite:0 alpha:0.40] setStroke]; p.lineWidth=1; [p stroke];
    });
}
- (void)place:(BOOL)animated {
    CGRect f=_strip.frame; f.origin.x=_on?0:-(kSwW-kKnob);
    if (animated) [UIView animateWithDuration:0.18 animations:^{ self->_strip.frame=f; }];
    else _strip.frame=f;
}
- (void)setOn:(BOOL)on { [self setOn:on animated:NO]; }
- (void)setOn:(BOOL)on animated:(BOOL)animated { _on=on; [self place:animated]; }
- (void)tapped { [self setOn:!_on animated:YES]; [self sendActionsForControlEvents:UIControlEventValueChanged]; }
@end

#pragma mark - Alert

static NSMutableArray *gShown;   // keeps alerts/sheets alive while visible (callers don't hold them)

static void sendIdx(id d, SEL s, id sender, NSInteger i) {
    if (d && [d respondsToSelector:s]) ((void(*)(id,SEL,id,NSInteger))objc_msgSend)(d,s,sender,i);
}
static UIWindow *overlayWindow(void) {
    UIWindow *w=[[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    w.windowLevel=UIWindowLevelAlert;
    w.backgroundColor=[UIColor clearColor];
    w.overrideUserInterfaceStyle=UIUserInterfaceStyleLight;
    UIViewController *vc=[UIViewController new]; vc.view.backgroundColor=[UIColor clearColor];
    w.rootViewController=vc;
    return w;
}
static UIButton *glossButton(NSString *title, UIColor *base, UIColor *textColor, CGFloat fontSize, CGFloat radius, BOOL lightText) {
    UIButton *b=[UIButton buttonWithType:UIButtonTypeCustom];
    [b setBackgroundImage:MMRetroGlossImage(base,CGSizeMake(2*radius+5,44),radius,NO) forState:UIControlStateNormal];
    [b setBackgroundImage:MMRetroGlossImage(base,CGSizeMake(2*radius+5,44),radius,YES) forState:UIControlStateHighlighted];
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:textColor forState:UIControlStateNormal];
    b.titleLabel.font=helv(fontSize,YES);
    b.titleLabel.adjustsFontSizeToFitWidth=YES; b.titleLabel.minimumScaleFactor=0.6;
    [b setTitleShadowColor:lightText?[UIColor colorWithWhite:0 alpha:0.5]:[UIColor colorWithWhite:1 alpha:0.6] forState:UIControlStateNormal];
    b.titleLabel.shadowOffset=CGSizeMake(0,lightText?-1:1);
    return b;
}

@implementation MMAlertView {
    NSMutableArray *_titles; UIWindow *_win; UIView *_box; UIView *_dim;
}
- (instancetype)initWithTitle:(NSString *)title message:(NSString *)message delegate:(id)delegate
            cancelButtonTitle:(NSString *)cancel otherButtonTitles:(NSString *)other, ... {
    self=[super initWithFrame:CGRectZero];
    if (self) {
        _title=[title copy]; _message=[message copy]; _delegate=delegate;
        _titles=[NSMutableArray array]; _cancelButtonIndex=-1;
        if (cancel) { [_titles addObject:cancel]; _cancelButtonIndex=0; }
        if (other) {
            [_titles addObject:other];
            va_list ap; va_start(ap,other); NSString *s;
            while ((s=va_arg(ap,NSString *))) [_titles addObject:s];
            va_end(ap);
        }
    }
    return self;
}
- (NSInteger)numberOfButtons { return (NSInteger)_titles.count; }
- (NSInteger)firstOtherButtonIndex {
    for (NSInteger i=0;i<(NSInteger)_titles.count;i++) if (i!=_cancelButtonIndex) return i;
    return -1;
}
- (NSInteger)addButtonWithTitle:(NSString *)t { [_titles addObject:t?:@""]; return (NSInteger)_titles.count-1; }
- (NSString *)buttonTitleAtIndex:(NSInteger)i { return (i>=0 && i<(NSInteger)_titles.count)?_titles[i]:nil; }
- (BOOL)isVisible { return _win!=nil; }

static UIImage *alertBoxImage(CGSize s) {
    return drawImage(s, ^(CGContextRef ctx){
        CGRect r=CGRectInset(CGRectMake(0,0,s.width,s.height),3,3);
        UIBezierPath *outer=[UIBezierPath bezierPathWithRoundedRect:r cornerRadius:10];
        CGContextSetShadowWithColor(ctx,CGSizeMake(0,2),3,[UIColor colorWithWhite:0 alpha:0.6].CGColor);
        [[UIColor colorWithWhite:1 alpha:0.85] setFill]; [outer fill];
        CGContextSetShadowWithColor(ctx,CGSizeZero,0,NULL);
        UIBezierPath *body=[UIBezierPath bezierPathWithRoundedRect:CGRectInset(r,2,2) cornerRadius:8];
        CGContextSaveGState(ctx); [body addClip];
        CGFloat locs[]={0,1};
        fillGradient(ctx,r,@[[UIColor colorWithRed:0.16 green:0.24 blue:0.45 alpha:1],[UIColor colorWithRed:0.03 green:0.08 blue:0.24 alpha:1]],locs);
        // glossy arc in the top part
        UIBezierPath *gloss=[UIBezierPath bezierPathWithOvalInRect:CGRectMake(-r.size.width*0.3,-60,r.size.width*1.6,100)];
        [gloss addClip];
        fillGradient(ctx,CGRectMake(0,0,s.width,40),@[[UIColor colorWithWhite:1 alpha:0.32],[UIColor colorWithWhite:1 alpha:0.08]],locs);
        CGContextRestoreGState(ctx);
    });
}

- (void)show {
    if (_win) return;
    if (!gShown) gShown=[NSMutableArray array];
    [gShown addObject:self];
    _win=overlayWindow();
    UIView *root=_win.rootViewController.view;
    CGSize S=root.bounds.size;
    _dim=[[UIView alloc] initWithFrame:root.bounds];
    _dim.backgroundColor=[UIColor colorWithWhite:0 alpha:0.45];
    [root addSubview:_dim];

    CGFloat BW=284, pad=12, inner=BW-2*pad-6, y=pad+8;
    _box=[[UIView alloc] initWithFrame:CGRectZero];
    UIImageView *bg=[[UIImageView alloc] init]; [_box addSubview:bg];
    NSShadow *sh=textShadow([UIColor colorWithWhite:0 alpha:0.5],-1);
    if (_title.length) {
        UILabel *t=[[UILabel alloc] init]; t.numberOfLines=0; t.textAlignment=NSTextAlignmentCenter;
        t.attributedText=[[NSAttributedString alloc] initWithString:_title attributes:@{NSFontAttributeName:helv(18,YES),NSForegroundColorAttributeName:[UIColor whiteColor],NSShadowAttributeName:sh}];
        CGSize ts=[t sizeThatFits:CGSizeMake(inner,1000)];
        t.frame=CGRectMake(pad+3,y,inner,ceil(ts.height)); [_box addSubview:t]; y+=ceil(ts.height)+6;
    }
    if (_message.length) {
        UILabel *m=[[UILabel alloc] init]; m.numberOfLines=0; m.textAlignment=NSTextAlignmentCenter;
        m.attributedText=[[NSAttributedString alloc] initWithString:_message attributes:@{NSFontAttributeName:helv(16,NO),NSForegroundColorAttributeName:[UIColor whiteColor],NSShadowAttributeName:sh}];
        CGSize ms=[m sizeThatFits:CGSizeMake(inner,S.height*0.5)];
        m.frame=CGRectMake(pad+3,y,inner,ceil(MIN(ms.height,S.height*0.5))); [_box addSubview:m]; y+=m.frame.size.height+6;
    }
    y+=8;
    NSInteger n=(NSInteger)_titles.count;
    UIColor *btn=[UIColor colorWithRed:0.30 green:0.38 blue:0.58 alpha:1], *cancelC=[UIColor colorWithRed:0.17 green:0.23 blue:0.40 alpha:1];
    if (n==2) {   // side by side, cancel on the left
        CGFloat bw=(inner-8)/2;
        for (NSInteger i=0;i<2;i++) {
            UIButton *b=glossButton(_titles[i],(i==_cancelButtonIndex)?cancelC:btn,[UIColor whiteColor],17,6,YES);
            b.frame=CGRectMake(pad+3+i*(bw+8),y,bw,43); b.tag=i;
            [b addTarget:self action:@selector(tap:) forControlEvents:UIControlEventTouchUpInside]; [_box addSubview:b];
        }
        y+=43;
    } else {
        // stacked; cancel last
        NSMutableArray *order=[NSMutableArray array];
        for (NSInteger i=0;i<n;i++) if (i!=_cancelButtonIndex) [order addObject:@(i)];
        if (_cancelButtonIndex>=0 && _cancelButtonIndex<n) [order addObject:@(_cancelButtonIndex)];
        for (NSNumber *num in order) {
            NSInteger i=num.integerValue;
            UIButton *b=glossButton(_titles[i],(i==_cancelButtonIndex)?cancelC:btn,[UIColor whiteColor],17,6,YES);
            b.frame=CGRectMake(pad+3,y,inner,43); b.tag=i;
            [b addTarget:self action:@selector(tap:) forControlEvents:UIControlEventTouchUpInside]; [_box addSubview:b];
            y+=43+8;
        }
        if (n) y-=8;
    }
    y+=pad+6;
    _box.frame=CGRectMake(floor((S.width-BW)/2),floor((S.height-y)/2)-10,BW,y);
    bg.frame=_box.bounds; bg.image=alertBoxImage(_box.bounds.size);
    [root addSubview:_box];
    _win.hidden=NO;

    _dim.alpha=0; _box.alpha=0; _box.transform=CGAffineTransformMakeScale(0.6,0.6);
    [UIView animateWithDuration:0.16 animations:^{ self->_dim.alpha=1; self->_box.alpha=1; self->_box.transform=CGAffineTransformMakeScale(1.08,1.08); }
                     completion:^(BOOL f){ [UIView animateWithDuration:0.1 animations:^{ self->_box.transform=CGAffineTransformMakeScale(0.96,0.96); }
                     completion:^(BOOL f2){ [UIView animateWithDuration:0.08 animations:^{ self->_box.transform=CGAffineTransformIdentity; }]; }]; }];
}
- (void)tap:(UIButton *)b {
    NSInteger i=b.tag;
    sendIdx(_delegate,@selector(alertView:clickedButtonAtIndex:),self,i);
    [self dismissWithClickedButtonIndex:i animated:YES];
}
- (void)dismissWithClickedButtonIndex:(NSInteger)i animated:(BOOL)animated {
    if (!_win) return;
    sendIdx(_delegate,@selector(alertView:willDismissWithButtonIndex:),self,i);
    UIWindow *w=_win;
    void (^finish)(void)=^{
        w.hidden=YES; self->_win=nil;
        sendIdx(self->_delegate,@selector(alertView:didDismissWithButtonIndex:),self,i);
        [gShown removeObject:self];
    };
    if (animated) [UIView animateWithDuration:0.2 animations:^{ self->_dim.alpha=0; self->_box.alpha=0; } completion:^(BOOL f){ finish(); }];
    else finish();
}
@end

#pragma mark - Action sheet

@implementation MMActionSheet {
    NSMutableArray *_titles; UIWindow *_win; UIView *_panel; UIView *_dim;
}
- (instancetype)initWithTitle:(NSString *)title delegate:(id)delegate cancelButtonTitle:(NSString *)cancel
       destructiveButtonTitle:(NSString *)destructive otherButtonTitles:(NSString *)other, ... {
    self=[super initWithFrame:CGRectZero];
    if (self) {
        _title=[title copy]; _delegate=delegate; _titles=[NSMutableArray array];
        _cancelButtonIndex=-1; _destructiveButtonIndex=-1;
        if (destructive) { [_titles addObject:destructive]; _destructiveButtonIndex=0; }
        if (other) {
            [_titles addObject:other];
            va_list ap; va_start(ap,other); NSString *s;
            while ((s=va_arg(ap,NSString *))) [_titles addObject:s];
            va_end(ap);
        }
        if (cancel) { [_titles addObject:cancel]; _cancelButtonIndex=(NSInteger)_titles.count-1; }
    }
    return self;
}
- (NSInteger)numberOfButtons { return (NSInteger)_titles.count; }
- (NSInteger)firstOtherButtonIndex {
    for (NSInteger i=0;i<(NSInteger)_titles.count;i++) if (i!=_cancelButtonIndex && i!=_destructiveButtonIndex) return i;
    return -1;
}
- (NSInteger)addButtonWithTitle:(NSString *)t { [_titles addObject:t?:@""]; return (NSInteger)_titles.count-1; }
- (NSString *)buttonTitleAtIndex:(NSInteger)i { return (i>=0 && i<(NSInteger)_titles.count)?_titles[i]:nil; }
- (void)showFromRect:(CGRect)rect inView:(UIView *)view animated:(BOOL)animated { [self showInView:view]; }
- (void)showInView:(UIView *)view {
    if (_win) return;
    if (!gShown) gShown=[NSMutableArray array];
    [gShown addObject:self];
    _win=overlayWindow();
    UIView *root=_win.rootViewController.view;
    CGSize S=root.bounds.size;
    _dim=[[UIView alloc] initWithFrame:root.bounds];
    _dim.backgroundColor=[UIColor colorWithWhite:0 alpha:0.4];
    [_dim addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapOutside)]];
    [root addSubview:_dim];

    CGFloat PW=MIN(S.width,480), side=20, bw=PW-2*side, y=14;
    _panel=[[UIView alloc] initWithFrame:CGRectZero];
    UIImageView *bg=[[UIImageView alloc] init]; [_panel addSubview:bg];
    if (_title.length) {
        UILabel *t=[[UILabel alloc] init]; t.numberOfLines=0; t.textAlignment=NSTextAlignmentCenter;
        t.attributedText=[[NSAttributedString alloc] initWithString:_title attributes:@{NSFontAttributeName:helv(13,NO),NSForegroundColorAttributeName:gray(0.85),NSShadowAttributeName:textShadow([UIColor colorWithWhite:0 alpha:0.5],-1)}];
        CGSize ts=[t sizeThatFits:CGSizeMake(bw,400)];
        t.frame=CGRectMake(side,y,bw,ceil(ts.height)); [_panel addSubview:t]; y+=ceil(ts.height)+12;
    }
    NSInteger n=(NSInteger)_titles.count;
    for (NSInteger i=0;i<n;i++) {
        if (i==_cancelButtonIndex) y+=8;
        UIButton *b;
        if (i==_destructiveButtonIndex) b=glossButton(_titles[i],[UIColor colorWithRed:0.80 green:0.10 blue:0.10 alpha:1],[UIColor whiteColor],19,8,YES);
        else if (i==_cancelButtonIndex) b=glossButton(_titles[i],gray(0.17),[UIColor whiteColor],19,8,YES);
        else b=glossButton(_titles[i],gray(0.90),[UIColor blackColor],19,8,NO);
        b.frame=CGRectMake(side,y,bw,44); b.tag=i;
        [b addTarget:self action:@selector(tap:) forControlEvents:UIControlEventTouchUpInside]; [_panel addSubview:b];
        y+=44+8;
    }
    y+=12;
    _panel.frame=CGRectMake(floor((S.width-PW)/2),S.height,PW,y);
    bg.frame=_panel.bounds;
    bg.image=drawImage(_panel.bounds.size, ^(CGContextRef ctx){
        CGRect r=CGRectMake(0,0,PW,y); CGFloat locs[]={0,1};
        fillGradient(ctx,r,@[[UIColor colorWithRed:0.25 green:0.27 blue:0.32 alpha:0.96],[UIColor colorWithRed:0.08 green:0.09 blue:0.11 alpha:0.97]],locs);
        [[UIColor colorWithWhite:1 alpha:0.35] setFill]; UIRectFill(CGRectMake(0,0,PW,1));
        [[UIColor colorWithWhite:0 alpha:0.8] setFill]; UIRectFill(CGRectMake(0,1,PW,1));
    });
    [root addSubview:_panel];
    _win.hidden=NO;
    _dim.alpha=0;
    [UIView animateWithDuration:0.25 animations:^{ self->_dim.alpha=1; CGRect f=self->_panel.frame; f.origin.y=S.height-y; self->_panel.frame=f; }];
}
- (void)tapOutside { if (_cancelButtonIndex>=0) { sendIdx(_delegate,@selector(actionSheet:clickedButtonAtIndex:),self,_cancelButtonIndex); [self dismissWithClickedButtonIndex:_cancelButtonIndex animated:YES]; } }
- (void)tap:(UIButton *)b {
    NSInteger i=b.tag;
    sendIdx(_delegate,@selector(actionSheet:clickedButtonAtIndex:),self,i);
    [self dismissWithClickedButtonIndex:i animated:YES];
}
- (void)dismissWithClickedButtonIndex:(NSInteger)i animated:(BOOL)animated {
    if (!_win) return;
    sendIdx(_delegate,@selector(actionSheet:willDismissWithButtonIndex:),self,i);
    UIWindow *w=_win; CGFloat H=_win.bounds.size.height;
    void (^finish)(void)=^{
        w.hidden=YES; self->_win=nil;
        sendIdx(self->_delegate,@selector(actionSheet:didDismissWithButtonIndex:),self,i);
        [gShown removeObject:self];
    };
    if (animated) [UIView animateWithDuration:0.22 animations:^{ self->_dim.alpha=0; CGRect f=self->_panel.frame; f.origin.y=H; self->_panel.frame=f; } completion:^(BOOL f){ finish(); }];
    else finish();
}
@end

#endif
