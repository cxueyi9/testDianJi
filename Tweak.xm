#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import "PTFakeMetaTouch.h"
#import "UITouch-KIFAdditions.h"

// ============================================
// 前向声明
// ============================================
@class AutoClickFloatingWindow;

// ============================================
// 辅助函数
// ============================================
static UIWindow* GetKeyWindow(void) {
    UIWindow *window = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *ws = (UIWindowScene *)scene;
                if (ws.activationState == UISceneActivationStateForegroundActive) {
                    for (UIWindow *w in ws.windows) {
                        if ([NSStringFromClass([w class]) isEqualToString:@"AutoClickFloatingWindow"]) {
                            continue;
                        }
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
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            if (![NSStringFromClass([w class]) isEqualToString:@"AutoClickFloatingWindow"]) {
                window = w;
                break;
            }
        }
    }
    return window;
}

// ============================================
// 配置管理
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
// 标记点击位置（红色圆点）
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
// 自定义 UIWindow（穿透）
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
// 设置页面 ViewController
// ============================================
@interface AutoClickSettingsViewController : UIViewController <UITextFieldDelegate>
@property (nonatomic, strong) UITextField *xField;
@property (nonatomic, strong) UITextField *yField;
@property (nonatomic, strong) UILabel *floatPosLabel;
@end

@implementation AutoClickSettingsViewController
// ... 与之前相同，略，请保留完整代码
// (直接复制之前的实现)
@end

// ============================================
// 悬浮窗视图
// ============================================
@interface AutoClickFloatingView : UIView
@property (nonatomic, weak) id target;
@property (nonatomic, assign) SEL action;
@end

@implementation AutoClickFloatingView
// ... 与之前相同
@end

// ============================================
// 主管理器
// ============================================
@interface AutoClickManager : NSObject
+ (instancetype)sharedManager;
- (void)performClick;
- (UIView *)findFloatViewInView:(UIView *)view;
- (void)sendTapAtPoint:(CGPoint)point;
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

// ---- 递归查找 FloatView ----
- (UIView *)findFloatViewInView:(UIView *)view {
    if ([NSStringFromClass([view class]) isEqualToString:@"FloatView"]) {
        return view;
    }
    for (UIView *sub in view.subviews) {
        UIView *result = [self findFloatViewInView:sub];
        if (result) return result;
    }
    return nil;
}

// ---- 使用 PTFakeTouch 发送点击 ----
- (void)sendTapAtPoint:(CGPoint)point {
    NSLog(@"[AutoClick] 📱 Sending PTFakeTouch at (%.0f,%.0f)", point.x, point.y);
    NSInteger pointId = [PTFakeMetaTouch fakeTouchId:0 AtPoint:point withTouchPhase:UITouchPhaseBegan];
    if (pointId > 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.05 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [PTFakeMetaTouch fakeTouchId:pointId AtPoint:point withTouchPhase:UITouchPhaseEnded];
            NSLog(@"[AutoClick] ✅ PTFakeTouch tap sent");
        });
    } else {
        NSLog(@"[AutoClick] ❌ PTFakeTouch failed");
    }
}

- (void)performClick {
    CGPoint point = CGPointMake(gClickX, gClickY);
    NSLog(@"[AutoClick] 🚀 Perform click at (%.0f, %.0f)", point.x, point.y);
    showTapMarkerAtPoint(point);
    
    // ---- 策略1: 查找 FloatView ----
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if ([NSStringFromClass([w class]) isEqualToString:@"AutoClickFloatingWindow"]) {
            continue;
        }
        UIView *floatView = [self findFloatViewInView:w];
        if (floatView) {
            NSLog(@"[AutoClick] 🎯 Found FloatView in window: %@", NSStringFromClass([w class]));
            // 获取 FloatView 中心点屏幕坐标
            CGPoint center = CGPointMake(CGRectGetMidX(floatView.bounds), CGRectGetMidY(floatView.bounds));
            CGPoint screenCenter = [floatView convertPoint:center toView:nil];
            NSLog(@"[AutoClick] 📐 FloatView center at screen: (%.0f,%.0f)", screenCenter.x, screenCenter.y);
            [self sendTapAtPoint:screenCenter];
            return;
        }
    }
    
    // ---- 策略2: 如果没找到 FloatView，使用普通 hitTest 且只对 UIControl 做安全操作 ----
    UIView *hitView = nil;
    CGPoint hitPoint = CGPointZero;
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if ([NSStringFromClass([w class]) isEqualToString:@"AutoClickFloatingWindow"]) {
            continue;
        }
        if (w.hidden) continue;
        CGPoint windowPoint = [w convertPoint:point fromWindow:nil];
        UIView *view = [w hitTest:windowPoint withEvent:nil];
        if (view && ![view isKindOfClass:NSClassFromString(@"FlutterView")] && ![view isKindOfClass:[UIWindow class]]) {
            hitView = view;
            hitPoint = windowPoint;
            break;
        }
    }
    
    if (hitView) {
        NSLog(@"[AutoClick] 🎯 Found view via hitTest: %@", NSStringFromClass([hitView class]));
        // 如果是 UIControl，安全发送事件
        if ([hitView isKindOfClass:[UIControl class]]) {
            [(UIControl *)hitView sendActionsForControlEvents:UIControlEventTouchUpInside];
            NSLog(@"[AutoClick] ✅ UIControl action sent");
            return;
        }
        // 否则使用 PTFakeTouch 在 hitPoint 发送
        [self sendTapAtPoint:hitPoint];
    } else {
        NSLog(@"[AutoClick] ❌ No view found");
    }
}

@end

// ============================================
// dylib 入口
// ============================================
__attribute__((constructor)) static void entry(void) {
    [AutoClickManager sharedManager];
}