// MMRetro.h - iOS 6 look on modern iOS (MM_MODERN builds only).
// spofity was designed around the native iOS 5/6 controls (glossy bars, bordered buttons, ON/OFF switches,
// blue alerts). Modern UIKit draws all of those flat, so this file draws them the iOS 6 way instead.
#import <UIKit/UIKit.h>

#ifdef MM_MODERN

#ifdef __cplusplus
extern "C" {
#endif
// Once at launch, before any view exists: Helvetica as the system font, bar/slider/search appearance, status bar strip.
void MMRetroInstall(void);

// Status bar: dark = black iOS 6 status bar with white text; light = gray iOS 6 status bar with black text.
void MMStatusBarDark(BOOL dark);
void MMStatusBarHidden(BOOL hidden);

// Bars. tint == nil -> black gloss (UIBarStyleBlack). Optional texture replaces the gradient (dark mode stripe).
void MMRetroStyleNavBar(UINavigationBar *bar, UIColor *tint, UIImage *texture);
void MMRetroStyleToolbar(UIToolbar *bar, BOOL dark);
void MMRetroToolbarBackground(UIToolbar *bar, UIImage *image);   // e.g. mini player tinted by the cover
void MMRetroStyleTabBar(UITabBar *bar, UIColor *accent);
void MMRetroStyleSearchBar(UISearchBar *bar, BOOL dark);
void MMRetroStyleSlider(UISlider *slider, UIColor *accent);
void MMRetroStyleVolumeView(id volumeView, UIColor *accent);
void MMRetroStyleRoundedRectButton(UIButton *button);
void MMRetroStyleGroupedTable(UITableView *table);

// Bordered bar button (title or image), "Done" = blue. tint = bar colour (nil = black bar).
UIBarButtonItem *MMRetroBarItem(NSString *title, UIImage *image, BOOL done, UIColor *tint, id target, SEL action);
// Re-tint the bordered buttons of a bar after a theme change.
void MMRetroRetintItems(UINavigationItem *item, UIColor *tint);

// Wrap a root view controller so its view starts below the status bar (iOS 6 layout); Unwrap returns the inner one.
UIViewController *MMRetroBelowStatusBar(UIViewController *vc);
UIViewController *MMRetroUnwrap(UIViewController *vc);
UIImage *MMRetroPlusImage(void);

UIImage *MMRetroGlossImage(UIColor *base, CGSize size, CGFloat radius, BOOL pressed);
#ifdef __cplusplus
}
#endif

// iOS 6 ON/OFF switch. Same API as UISwitch for what spofity uses (on, setOn:animated:, onTintColor, ValueChanged).
@interface MMRetroSwitch : UIControl
@property (nonatomic, getter=isOn) BOOL on;
@property (nonatomic, strong) UIColor *onTintColor;
- (void)setOn:(BOOL)on animated:(BOOL)animated;
@end

// iOS 6 blue alert. Same API as UIAlertView for what spofity uses.
@interface MMAlertView : UIView
@property (nonatomic, weak) id delegate;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *message;
@property (nonatomic, readonly) NSInteger numberOfButtons;
@property (nonatomic) NSInteger cancelButtonIndex;
@property (nonatomic, readonly) NSInteger firstOtherButtonIndex;
@property (nonatomic, readonly, getter=isVisible) BOOL visible;
- (instancetype)initWithTitle:(NSString *)title message:(NSString *)message delegate:(id)delegate
            cancelButtonTitle:(NSString *)cancelButtonTitle otherButtonTitles:(NSString *)otherButtonTitles, ... NS_REQUIRES_NIL_TERMINATION;
- (NSInteger)addButtonWithTitle:(NSString *)title;
- (NSString *)buttonTitleAtIndex:(NSInteger)buttonIndex;
- (void)show;
- (void)dismissWithClickedButtonIndex:(NSInteger)buttonIndex animated:(BOOL)animated;
@end

// iOS 6 black action sheet. Same API as UIActionSheet for what spofity uses.
@interface MMActionSheet : UIView
@property (nonatomic, weak) id delegate;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, readonly) NSInteger numberOfButtons;
@property (nonatomic) NSInteger cancelButtonIndex;
@property (nonatomic) NSInteger destructiveButtonIndex;
@property (nonatomic, readonly) NSInteger firstOtherButtonIndex;
- (instancetype)initWithTitle:(NSString *)title delegate:(id)delegate cancelButtonTitle:(NSString *)cancelButtonTitle
       destructiveButtonTitle:(NSString *)destructiveButtonTitle otherButtonTitles:(NSString *)otherButtonTitles, ... NS_REQUIRES_NIL_TERMINATION;
- (NSInteger)addButtonWithTitle:(NSString *)title;
- (NSString *)buttonTitleAtIndex:(NSInteger)buttonIndex;
- (void)showInView:(UIView *)view;
- (void)showFromRect:(CGRect)rect inView:(UIView *)view animated:(BOOL)animated;
- (void)dismissWithClickedButtonIndex:(NSInteger)buttonIndex animated:(BOOL)animated;
@end

#endif
