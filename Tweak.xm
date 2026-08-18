#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <dlfcn.h>
#import <objc/message.h>

// ============================================
// 1. GSEvent 私有 API（系统级模拟）
// ============================================
typedef struct __GSEvent *GSEventRef;
typedef enum {
    kGSEventTypeTouchDown = 1,
    kGSEventTypeTouchUp   = 2,
} GSEventType;

typedef GSEventRef (*GSEventRecordCreateFunc)(GSEventType type, int subtype, CGPoint location, int unknown1, int unknown2, int unknown3);
typedef void (*GSEventDispatchFunc)(GSEventRef event);

static GSEventRecordCreateFunc GSEventRecordCreate = NULL;
static GSEventDispatchFunc     GSEventDispatch     = NULL;

static void initGSEvent(void) {
    void *handle = dlopen("/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices", RTLD_LAZY);
    if (handle) {
        GSEventRecordCreate = (GSEventRecordCreateFunc)dlsym(handle, "GSEventRecordCreate");
        GSEventDispatch     = (GSEventDispatchFunc)dlsym(handle, "GSEventDispatch");
        if (GSEventRecordCreate && GSEventDispatch) {
            NSLog(@"[AutoClick] GSEvent functions loaded successfully");
        } else {
            NSLog(@"[AutoClick] Failed to load GSEvent functions");
        }
    } else {
        NSLog(@"[AutoClick] GraphicsServices framework not found");
    }
}

// ----- GSEvent 模拟点击 -----
static void simulateTapWithGSEvent(CGPoint point) {
    if (!GSEventRecordCreate || !GSEventDispatch) {
        NSLog(@"[AutoClick] GSEvent not available");
        return;
    }
    // 按下
    GSEventRef down = GSEventRecordCreate(kGSEventTypeTouchDown, 0, point, 0, 0, 0);
    if (down) {
        GSEventDispatch(down);
    }
    // 抬起
    GSEventRef up = GSEventRecordCreate(kGSEventTypeTouchUp, 0, point, 0, 0, 0);
    if (up) {
        GSEventDispatch(up);
    }
    NSLog(@"[AutoClick] GSEvent simulated tap at (%.0f, %.0f)", point.x, point.y);
}

// ============================================
// 2. 备用方案：针对 UIControl 的模拟
// ============================================
static void simulateTapOnUIControlAtPoint(CGPoint point) {
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
    if (!window) {
        window = [[UIApplication sharedApplication].windows firstObject];
    }
    if (!window) {
        NSLog(@"[AutoClick] No window found");
        return;
    }

    // 转换坐标到窗口
    CGPoint pointInWindow = point;
    UIView *targetView = [window hitTest:pointInWindow withEvent:nil];
    if (!targetView) {
        NSLog(@"[AutoClick] No view at point (%.0f, %.0f)", pointInWindow.x, pointInWindow.y);
        return;
    }

    // 如果是 UIControl，发送 TouchUpInside 事件
    if ([targetView isKindOfClass:[UIControl class]]) {
        UIControl *control = (UIControl *)targetView;
        [control sendActionsForControlEvents:UIControlEventTouchUpInside];
        NSLog(@"[AutoClick] UIControl simulated: %@", control);
    } else {
        NSLog(@"[AutoClick] View at point is not a UIControl: %@", targetView);
    }
}

// ============================================
// 3. 配置管理（同前，略）
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
}

// ============================================
// 4. 自定义 UIWindow（穿透）
// ============================================
@interface AutoClickFloatingWindow : UIWindow
@end

@implementation AutoClickFloatingWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    if (hitView == self || hitView == self.rootViewController.view) {
        for (UIView *subview in self.rootViewController.view.subviews) {
            CGPoint convertedPoint = [subview convertPoint:point fromView:self];
            if ([subview pointInside:convertedPoint withEvent:event]) {
                return subview;
            }
        }
        return nil;
    }
    return hitView;
}
@end

// ============================================
// 5. 设置页面（同前，略）
// ============================================
@interface AutoClickSettingsViewController : UIViewController <UITextFieldDelegate>
@property (nonatomic, strong) UITextField *xField;
@property (nonatomic, strong) UITextField *yField;
@property (nonatomic, strong) UILabel *floatPosLabel;
@end

@implementation AutoClickSettingsViewController
// ...（与之前完全相同，为节省篇幅略，但实际使用需完整复制）
// 您可以直接使用之前版本的此部分代码。
@end

// ============================================
// 6. 悬浮窗视图（同前，略）
// ============================================
@interface AutoClickFloatingView : UIView
@property (nonatomic, weak) id target;
@property (nonatomic, assign) SEL action;
@end

@implementation AutoClickFloatingView
// ...（与之前完全相同）
@end

// ============================================
// 7. 主管理器（点击时弹出提示）
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
    NSLog(@"[AutoClick] Perform click at (%.0f, %.0f)", point.x, point.y);

    // ----- 弹出提示框，确认点击触发 -----
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *topVC = [self topMostViewController];
        if (topVC) {
            NSString *msg = [NSString stringWithFormat:@"已点击 (%.0f, %.0f)", point.x, point.y];
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"AutoClick"
                                                                           message:msg
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
            [topVC presentViewController:alert animated:YES completion:nil];
        } else {
            NSLog(@"[AutoClick] No view controller to present alert");
        }
    });

    // ----- 模拟点击（双重策略）-----
    // 1. 先尝试 GSEvent（系统级）
    simulateTapWithGSEvent(point);

    // 2. 再尝试 UIControl 模拟（针对按钮等）
    simulateTapOnUIControlAtPoint(point);
}

- (UIViewController *)topMostViewController {
    UIWindow *keyWindow = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *ws = (UIWindowScene *)scene;
                if (ws.activationState == UISceneActivationStateForegroundActive) {
                    keyWindow = ws.keyWindow;
                    if (keyWindow) break;
                }
            }
        }
    } else {
        keyWindow = [UIApplication sharedApplication].keyWindow;
    }
    if (!keyWindow) {
        keyWindow = [[UIApplication sharedApplication].windows firstObject];
    }
    UIViewController *topVC = keyWindow.rootViewController;
    while (topVC.presentedViewController) {
        topVC = topVC.presentedViewController;
    }
    return topVC;
}

@end

// ============================================
// 8. 入口
// ============================================
__attribute__((constructor)) static void entry(void) {
    initGSEvent();
    [AutoClickManager sharedManager];
}