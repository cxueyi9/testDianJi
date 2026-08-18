#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <dlfcn.h>
#import <objc/message.h>

// ============================================
// 0. 前置声明：获取当前窗口的 C 函数
// ============================================
static UIWindow* GetKeyWindow(void) {
    UIWindow *window = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *ws = (UIWindowScene *)scene;
                if (ws.activationState == UISceneActivationStateForegroundActive) {
                    for (UIWindow *w in ws.windows) {
                        if (w.isKeyWindow) {
                            window = w;
                            break;
                        }
                    }
                    if (window) break;
                }
            }
        }
    } else {
        window = [UIApplication sharedApplication].keyWindow;
    }
    if (!window) window = [[UIApplication sharedApplication].windows firstObject];
    return window;
}

// ============================================
// 1. GSEvent 私有 API
// ============================================
typedef struct __GSEvent *GSEventRef;
typedef enum {
    kGSEventTypeTouchDown = 1,
    kGSEventTypeTouchUp   = 2,
} GSEventType;

static GSEventRef (*GSEventRecordCreate)(GSEventType type, int subtype, CGPoint location, int unknown1, int unknown2, int unknown3) = NULL;
static void (*GSEventRecordSetPathInfo)(GSEventRef event, CFArrayRef pathInfo) = NULL;
static void (*GSEventDispatch)(GSEventRef event) = NULL;

static void initGSEvent(void) {
    void *handle = dlopen("/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices", RTLD_LAZY);
    if (handle) {
        GSEventRecordCreate = (typeof(GSEventRecordCreate))dlsym(handle, "GSEventRecordCreate");
        GSEventRecordSetPathInfo = (typeof(GSEventRecordSetPathInfo))dlsym(handle, "GSEventRecordSetPathInfo");
        GSEventDispatch = (typeof(GSEventDispatch))dlsym(handle, "GSEventDispatch");
        if (GSEventRecordCreate && GSEventDispatch && GSEventRecordSetPathInfo) {
            NSLog(@"[AutoClick] ✅ GSEvent fully loaded");
        } else {
            NSLog(@"[AutoClick] ❌ GSEvent load incomplete");
        }
    } else {
        NSLog(@"[AutoClick] ❌ GraphicsServices framework not found");
    }
}

// 模拟点击（两种方式）
static void simulateTapWithGSEvent(CGPoint point) {
    if (!GSEventRecordCreate || !GSEventDispatch) {
        NSLog(@"[AutoClick] ⚠️ GSEvent not available, skip");
        return;
    }
    // 方式1：不带路径
    GSEventRef down1 = GSEventRecordCreate(kGSEventTypeTouchDown, 0, point, 0, 0, 0);
    if (down1) { GSEventDispatch(down1); }
    GSEventRef up1 = GSEventRecordCreate(kGSEventTypeTouchUp, 0, point, 0, 0, 0);
    if (up1) { GSEventDispatch(up1); }
    NSLog(@"[AutoClick] 👆 GSEvent tap (no path)");

    // 方式2：带路径
    CFMutableArrayRef path = CFArrayCreateMutable(NULL, 1, &kCFTypeArrayCallBacks);
    CFArrayAppendValue(path, (const void *)(intptr_t)0);
    GSEventRef down2 = GSEventRecordCreate(kGSEventTypeTouchDown, 0, point, 0, 0, 0);
    if (down2) {
        if (GSEventRecordSetPathInfo) GSEventRecordSetPathInfo(down2, path);
        GSEventDispatch(down2);
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.05 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        GSEventRef up2 = GSEventRecordCreate(kGSEventTypeTouchUp, 0, point, 0, 0, 0);
        if (up2) {
            if (GSEventRecordSetPathInfo) GSEventRecordSetPathInfo(up2, path);
            GSEventDispatch(up2);
        }
        CFRelease(path);
        NSLog(@"[AutoClick] 👆 GSEvent tap (with path)");
    });
}

// ============================================
// 2. UIControl 模拟
// ============================================
static void simulateTapOnUIControlAtPoint(CGPoint point) {
    UIWindow *window = GetKeyWindow();
    if (!window) {
        NSLog(@"[AutoClick] ❌ No window found for UIControl");
        return;
    }
    CGPoint windowPoint = [window convertPoint:point fromWindow:nil];
    NSLog(@"[AutoClick] 📐 Screen(%.0f,%.0f) -> Window(%.0f,%.0f)", point.x, point.y, windowPoint.x, windowPoint.y);
    UIView *targetView = [window hitTest:windowPoint withEvent:nil];
    if (targetView) {
        NSLog(@"[AutoClick] 🎯 hitTest: %@ (class: %@)", targetView, NSStringFromClass([targetView class]));
        if ([targetView isKindOfClass:[UIControl class]]) {
            [(UIControl *)targetView sendActionsForControlEvents:UIControlEventTouchUpInside];
            NSLog(@"[AutoClick] ✅ UIControl action sent");
        } else {
            NSLog(@"[AutoClick] ⚠️ View is not UIControl");
        }
    } else {
        NSLog(@"[AutoClick] ❌ No view at point");
    }
}

// ============================================
// 3. 标记点击位置（红色圆点）
// ============================================
static void showTapMarkerAtPoint(CGPoint point) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = GetKeyWindow();
        if (!window) return;
        UIView *marker = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 30, 30)];
        marker.center = point;
        marker.backgroundColor = [UIColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:0.7];
        marker.layer.cornerRadius = 15;
        marker.layer.borderWidth = 2;
        marker.layer.borderColor = [UIColor whiteColor].CGColor;
        marker.userInteractionEnabled = NO;
        marker.tag = 9999;
        UIView *oldMarker = [window viewWithTag:9999];
        if (oldMarker) [oldMarker removeFromSuperview];
        [window addSubview:marker];
        NSLog(@"[AutoClick] 🔴 Marker at (%.0f,%.0f)", point.x, point.y);
        [UIView animateWithDuration:0.5 delay:0.5 options:UIViewAnimationOptionCurveEaseOut animations:^{
            marker.alpha = 0.0;
        } completion:^(BOOL finished) {
            [marker removeFromSuperview];
        }];
    });
}

// ============================================
// 4. 配置管理（省略，与之前相同）
// ============================================
static NSString *const kConfigFileName = @"autoclick_config.plist";
static CGFloat gClickX = 100.0;
static CGFloat gClickY = 100.0;
static CGFloat gFloatX = 100.0;
static CGFloat gFloatY = 100.0;
static const CGFloat kFloatSize = 60.0;

static void loadConfig(void) {
    NSString *docPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *configPath = [docPath stringByAppendingPathComponent:kConfigFileName];
    NSDictionary *config = [NSDictionary dictionaryWithContentsOfFile:configPath];
    if (config) {
        if (config[@"clickX"]) gClickX = [config[@"clickX"] doubleValue];
        if (config[@"clickY"]) gClickY = [config[@"clickY"] doubleValue];
        if (config[@"floatX"]) gFloatX = [config[@"floatX"] doubleValue];
        if (config[@"floatY"]) gFloatY = [config[@"floatY"] doubleValue];
        NSLog(@"[AutoClick] 📂 Config loaded: click(%.0f,%.0f) float(%.0f,%.0f)", gClickX, gClickY, gFloatX, gFloatY);
    } else {
        NSLog(@"[AutoClick] 📂 No config, using defaults");
    }
    CGRect screen = [UIScreen mainScreen].bounds;
    gFloatX = MAX(0, MIN(gFloatX, screen.size.width - kFloatSize));
    gFloatY = MAX(0, MIN(gFloatY, screen.size.height - kFloatSize));
}

static void saveConfig(void) {
    NSDictionary *config = @{
        @"clickX": @(gClickX),
        @"clickY": @(gClickY),
        @"floatX": @(gFloatX),
        @"floatY": @(gFloatY)
    };
    NSString *docPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *configPath = [docPath stringByAppendingPathComponent:kConfigFileName];
    [config writeToFile:configPath atomically:YES];
    NSLog(@"[AutoClick] 💾 Config saved");
}

// ============================================
// 5. 自定义 UIWindow（穿透）—— 略，同前
// ============================================
@interface AutoClickFloatingWindow : UIWindow @end
@implementation AutoClickFloatingWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    if (hitView == self || hitView == self.rootViewController.view) {
        for (UIView *subview in self.rootViewController.view.subviews) {
            CGPoint converted = [subview convertPoint:point fromView:self];
            if ([subview pointInside:converted withEvent:event]) return subview;
        }
        return nil;
    }
    return hitView;
}
@end

// ============================================
// 6. 设置页面 ViewController（略，同前）
// ============================================
@interface AutoClickSettingsViewController : UIViewController <UITextFieldDelegate>
@property (nonatomic, strong) UITextField *xField;
@property (nonatomic, strong) UITextField *yField;
@property (nonatomic, strong) UILabel *floatPosLabel;
@end
// ... 实现与之前完全相同（省略节省篇幅，但实际使用需完整复制）
// 注意：在实现中 topMostViewController 调用 GetKeyWindow() 而非 [AutoClickManager getKeyWindow]
// 您可以直接沿用之前的代码，但将 [AutoClickManager getKeyWindow] 替换为 GetKeyWindow()

// ============================================
// 7. 悬浮窗视图（略，同前，但 topMostViewController 改用 GetKeyWindow）
// ============================================
@interface AutoClickFloatingView : UIView
@property (nonatomic, weak) id target;
@property (nonatomic, assign) SEL action;
@end
// 实现中：UIWindow *keyWindow = GetKeyWindow();

// ============================================
// 8. 主管理器
// ============================================
@interface AutoClickManager : NSObject
+ (instancetype)sharedManager;
- (void)performClick;
@end

@implementation AutoClickManager {
    AutoClickFloatingWindow *_floatingWindow;
    AutoClickFloatingView *_floatingView;
}

+ (instancetype)sharedManager {
    static AutoClickManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[AutoClickManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        loadConfig();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self showFloatingWindow];
        });
    }
    return self;
}

- (void)showFloatingWindow {
    if (_floatingWindow) return;
    CGRect screen = [UIScreen mainScreen].bounds;
    CGRect frame = CGRectMake(gFloatX, gFloatY, kFloatSize, kFloatSize);
    _floatingWindow = [[AutoClickFloatingWindow alloc] initWithFrame:screen];
    _floatingWindow.windowLevel = UIWindowLevelAlert + 1;
    _floatingWindow.backgroundColor = [UIColor clearColor];
    _floatingWindow.rootViewController = [UIViewController new];
    _floatingWindow.rootViewController.view.backgroundColor = [UIColor clearColor];
    _floatingView = [[AutoClickFloatingView alloc] initWithFrame:frame];
    _floatingView.target = self;
    _floatingView.action = @selector(performClick);
    [_floatingWindow.rootViewController.view addSubview:_floatingView];
    _floatingWindow.hidden = NO;
}

- (void)performClick {
    CGPoint point = CGPointMake(gClickX, gClickY);
    NSLog(@"[AutoClick] 🚀 Perform click at (%.0f, %.0f)", point.x, point.y);
    showTapMarkerAtPoint(point);
    simulateTapOnUIControlAtPoint(point);
    simulateTapWithGSEvent(point);
}
@end

// ============================================
// 9. dylib 入口
// ============================================
__attribute__((constructor)) static void entry(void) {
    initGSEvent();
    [AutoClickManager sharedManager];
}