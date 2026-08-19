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
// 辅助函数：获取当前 key window（备用）
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

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    self.title = @"AutoClick 设置";

    UIBarButtonItem *closeBtn = [[UIBarButtonItem alloc] initWithTitle:@"关闭" style:UIBarButtonItemStylePlain target:self action:@selector(close)];
    self.navigationItem.leftBarButtonItem = closeBtn;

    CGFloat margin = 20;
    CGFloat yOffset = 100;
    CGFloat labelWidth = 80;
    CGFloat fieldWidth = 120;
    CGFloat height = 40;

    UILabel *xLabel = [[UILabel alloc] initWithFrame:CGRectMake(margin, yOffset, labelWidth, height)];
    xLabel.text = @"点击 X:";
    [self.view addSubview:xLabel];

    _xField = [[UITextField alloc] initWithFrame:CGRectMake(margin + labelWidth + 10, yOffset, fieldWidth, height)];
    _xField.borderStyle = UITextBorderStyleRoundedRect;
    _xField.keyboardType = UIKeyboardTypeDecimalPad;
    _xField.text = [NSString stringWithFormat:@"%.0f", gClickX];
    [self.view addSubview:_xField];

    yOffset += height + 20;
    UILabel *yLabel = [[UILabel alloc] initWithFrame:CGRectMake(margin, yOffset, labelWidth, height)];
    yLabel.text = @"点击 Y:";
    [self.view addSubview:yLabel];

    _yField = [[UITextField alloc] initWithFrame:CGRectMake(margin + labelWidth + 10, yOffset, fieldWidth, height)];
    _yField.borderStyle = UITextBorderStyleRoundedRect;
    _yField.keyboardType = UIKeyboardTypeDecimalPad;
    _yField.text = [NSString stringWithFormat:@"%.0f", gClickY];
    [self.view addSubview:_yField];

    yOffset += height + 30;
    UIButton *saveBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    saveBtn.frame = CGRectMake(margin, yOffset, 100, 40);
    [saveBtn setTitle:@"保存" forState:UIControlStateNormal];
    [saveBtn addTarget:self action:@selector(save) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:saveBtn];

    yOffset += 60;
    UILabel *floatLabel = [[UILabel alloc] initWithFrame:CGRectMake(margin, yOffset, 200, height)];
    floatLabel.text = @"悬浮窗左上角:";
    [self.view addSubview:floatLabel];

    _floatPosLabel = [[UILabel alloc] initWithFrame:CGRectMake(margin, yOffset + height + 5, 300, height)];
    _floatPosLabel.text = [NSString stringWithFormat:@"(%.0f, %.0f)", gFloatX, gFloatY];
    [self.view addSubview:_floatPosLabel];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    _floatPosLabel.text = [NSString stringWithFormat:@"(%.0f, %.0f)", gFloatX, gFloatY];
}

- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }

- (void)save {
    CGFloat x = [_xField.text doubleValue];
    CGFloat y = [_yField.text doubleValue];
    CGRect screen = [UIScreen mainScreen].bounds;
    if (x < 0 || x > screen.size.width || y < 0 || y > screen.size.height) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"坐标无效" message:@"请输入屏幕范围内的坐标" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    gClickX = x;
    gClickY = y;
    saveConfig();
    [self close];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}
@end

// ============================================
// 悬浮窗视图
// ============================================
@interface AutoClickFloatingView : UIView
@property (nonatomic, weak) id target;
@property (nonatomic, assign) SEL action;
@end

@implementation AutoClickFloatingView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.frame = self.bounds;
        btn.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:0.85];
        btn.layer.cornerRadius = frame.size.width / 2;
        [btn setTitle:@"▶" forState:UIControlStateNormal];
        [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont boldSystemFontOfSize:22];
        [btn addTarget:self action:@selector(buttonTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:btn];

        UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPress:)];
        [self addGestureRecognizer:longPress];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
        [self addGestureRecognizer:pan];
    }
    return self;
}

- (void)buttonTapped {
    if (self.target && [self.target respondsToSelector:self.action]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [self.target performSelector:self.action];
#pragma clang diagnostic pop
    }
}

- (void)longPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        UIViewController *topVC = [self topMostViewController];
        if (topVC) {
            AutoClickSettingsViewController *settingsVC = [[AutoClickSettingsViewController alloc] init];
            UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:settingsVC];
            [topVC presentViewController:nav animated:YES completion:nil];
        }
    }
}

- (void)pan:(UIPanGestureRecognizer *)gesture {
    CGPoint translation = [gesture translationInView:self.superview];
    CGPoint newCenter = CGPointMake(self.center.x + translation.x, self.center.y + translation.y);
    CGRect screen = [UIScreen mainScreen].bounds;
    CGFloat halfSize = self.frame.size.width / 2;
    newCenter.x = MAX(halfSize, MIN(newCenter.x, screen.size.width - halfSize));
    newCenter.y = MAX(halfSize, MIN(newCenter.y, screen.size.height - halfSize));
    self.center = newCenter;
    [gesture setTranslation:CGPointZero inView:self.superview];

    if (gesture.state == UIGestureRecognizerStateEnded) {
        gFloatX = self.frame.origin.x;
        gFloatY = self.frame.origin.y;
        saveConfig();
    }
}

- (UIViewController *)topMostViewController {
    UIWindow *keyWindow = GetKeyWindow();
    UIViewController *topVC = keyWindow.rootViewController;
    while (topVC.presentedViewController) {
        topVC = topVC.presentedViewController;
    }
    return topVC;
}
@end

// ============================================
// 主管理器
// ============================================
@interface AutoClickManager : NSObject
+ (instancetype)sharedManager;
- (void)performClick;
- (void)triggerTapOnView:(UIView *)view atPoint:(CGPoint)point;
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

// ---- 递归打印视图层级 ----
- (void)printViewHierarchy:(UIView *)view depth:(int)depth {
    if (!view) return;
    NSMutableString *indent = [NSMutableString string];
    for (int i = 0; i < depth; i++) [indent appendString:@"  "];
    NSLog(@"[AutoClick] %@%@ frame:%@, gestures:%lu", indent, NSStringFromClass([view class]), NSStringFromCGRect(view.frame), (unsigned long)view.gestureRecognizers.count);
    for (UIGestureRecognizer *g in view.gestureRecognizers) {
        NSLog(@"[AutoClick] %@  gesture: %@", indent, NSStringFromClass([g class]));
        id targets = [g valueForKey:@"targets"];
        if (targets) {
            NSArray *targetsArray = (NSArray *)targets;
            for (id targetObj in targetsArray) {
                id actionTarget = [targetObj valueForKey:@"target"];
                NSString *actionName = NSStringFromSelector(NSSelectorFromString([targetObj valueForKey:@"action"]));
                NSLog(@"[AutoClick] %@    target: %@, action: %@", indent, actionTarget, actionName);
            }
        }
    }
    for (UIView *sub in view.subviews) {
        [self printViewHierarchy:sub depth:depth+1];
    }
}

// ---- 触发点击（多方法尝试） ----
- (void)triggerTapOnView:(UIView *)view atPoint:(CGPoint)point {
    if (!view) {
        NSLog(@"[AutoClick] ❌ view is nil");
        return;
    }
    
    NSLog(@"[AutoClick] 🎯 ====== Triggering tap on %@ ======", NSStringFromClass([view class]));
    NSLog(@"[AutoClick] 📐 View frame: %@", NSStringFromCGRect(view.frame));
    NSLog(@"[AutoClick] 📐 Point: (%.0f,%.0f)", point.x, point.y);
    
    // ---- 打印所有手势识别器 ----
    NSLog(@"[AutoClick] 🖐 Gesture recognizers on view:");
    for (UIGestureRecognizer *gesture in view.gestureRecognizers) {
        NSLog(@"[AutoClick]   - %@", NSStringFromClass([gesture class]));
        if ([gesture isKindOfClass:[UITapGestureRecognizer class]]) {
            NSLog(@"[AutoClick]     -> UITapGestureRecognizer found!");
        }
    }
    
    // ---- 方法1: 直接触发 UITapGestureRecognizer ----
    for (UIGestureRecognizer *gesture in view.gestureRecognizers) {
        if ([gesture isKindOfClass:[UITapGestureRecognizer class]]) {
            NSLog(@"[AutoClick] ✅ Method 1: Triggering UITapGestureRecognizer directly");
            id targets = [gesture valueForKey:@"targets"];
            if (targets) {
                NSArray *targetsArray = (NSArray *)targets;
                for (id targetObj in targetsArray) {
                    id actionTarget = [targetObj valueForKey:@"target"];
                    SEL action = NSSelectorFromString([targetObj valueForKey:@"action"]);
                    if (actionTarget && action) {
                        @try {
                            // 使用 performSelector
                            if ([actionTarget respondsToSelector:action]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                                [actionTarget performSelector:action withObject:gesture];
#pragma clang diagnostic pop
                                NSLog(@"[AutoClick] ✅ Method 1: Action triggered on %@", actionTarget);
                                return;
                            }
                        } @catch (NSException *exception) {
                            NSLog(@"[AutoClick] ⚠️ Method 1 exception: %@", exception);
                        }
                    }
                }
            }
        }
    }
    
    // ---- 方法2: 如果是 UIImageView，查找父视图的 UIControl ----
    if ([view isKindOfClass:[UIImageView class]]) {
        UIView *parent = view.superview;
        while (parent) {
            if ([parent isKindOfClass:[UIControl class]]) {
                NSLog(@"[AutoClick] ✅ Method 2: Found UIControl parent: %@", NSStringFromClass([parent class]));
                @try {
                    [(UIControl *)parent sendActionsForControlEvents:UIControlEventTouchUpInside];
                    NSLog(@"[AutoClick] ✅ Method 2: UIControl action sent");
                    return;
                } @catch (NSException *exception) {
                    NSLog(@"[AutoClick] ⚠️ Method 2 exception: %@", exception);
                }
            }
            // 也检查父视图的手势
            for (UIGestureRecognizer *g in parent.gestureRecognizers) {
                if ([g isKindOfClass:[UITapGestureRecognizer class]]) {
                    id targets = [g valueForKey:@"targets"];
                    if (targets) {
                        NSArray *targetsArray = (NSArray *)targets;
                        for (id targetObj in targetsArray) {
                            id actionTarget = [targetObj valueForKey:@"target"];
                            SEL action = NSSelectorFromString([targetObj valueForKey:@"action"]);
                            if (actionTarget && action) {
                                @try {
                                    if ([actionTarget respondsToSelector:action]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                                        [actionTarget performSelector:action withObject:g];
#pragma clang diagnostic pop
                                        NSLog(@"[AutoClick] ✅ Method 2: Parent gesture triggered");
                                        return;
                                    }
                                } @catch (NSException *exception) {
                                    NSLog(@"[AutoClick] ⚠️ Method 2 exception: %@", exception);
                                }
                            }
                        }
                    }
                }
            }
            parent = parent.superview;
        }
    }
    
    // ---- 方法3: 模拟完整触摸事件（使用 PTFakeTouch） ----
    NSLog(@"[AutoClick] ✅ Method 3: Trying PTFakeTouch");
    NSInteger pointId = [PTFakeMetaTouch fakeTouchId:0 AtPoint:point withTouchPhase:UITouchPhaseBegan];
    if (pointId > 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.05 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [PTFakeMetaTouch fakeTouchId:pointId AtPoint:point withTouchPhase:UITouchPhaseEnded];
            NSLog(@"[AutoClick] ✅ Method 3: PTFakeTouch sent");
        });
        return;
    }
    
    // ---- 方法4: 直接调用 touchesBegan/Ended ----
    NSLog(@"[AutoClick] ✅ Method 4: Trying touchesBegan/Ended");
    UITouch *touch = [[UITouch alloc] initAtPoint:point inView:view];
    @try {
        [view touchesBegan:[NSSet setWithObject:touch] withEvent:nil];
        [view touchesEnded:[NSSet setWithObject:touch] withEvent:nil];
        NSLog(@"[AutoClick] ✅ Method 4: touchesBegan/Ended sent");
        return;
    } @catch (NSException *exception) {
        NSLog(@"[AutoClick] ⚠️ Method 4 exception: %@", exception);
    }
    
    NSLog(@"[AutoClick] ❌ All methods failed");
}

- (void)performClick {
    CGPoint point = CGPointMake(gClickX, gClickY);
    NSLog(@"[AutoClick] 🚀 Perform click at (%.0f, %.0f)", point.x, point.y);
    showTapMarkerAtPoint(point);
    
    // ---- 查找 level 1999 窗口并打印其视图层级 ----
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if ([NSStringFromClass([w class]) isEqualToString:@"AutoClickFloatingWindow"]) {
            continue;
        }
        if (w.windowLevel == 1999.0) {
            NSLog(@"[AutoClick] 🎯 Found window with level 1999: %@", NSStringFromClass([w class]));
            NSLog(@"[AutoClick] 📋 Printing view hierarchy of level 1999 window:");
            [self printViewHierarchy:w depth:0];
            
            // 尝试点击根视图
            UIView *rootView = w.rootViewController.view;
            if (rootView) {
                CGPoint localPoint = [rootView convertPoint:point fromView:nil];
                UIView *hitView = [rootView hitTest:localPoint withEvent:nil];
                if (hitView && hitView != rootView) {
                    [self triggerTapOnView:hitView atPoint:localPoint];
                    return;
                } else {
                    [self triggerTapOnView:rootView atPoint:localPoint];
                    return;
                }
            }
        }
    }
    
    // ---- 如果没找到 level 1999，尝试普通 hitTest ----
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if ([NSStringFromClass([w class]) isEqualToString:@"AutoClickFloatingWindow"]) {
            continue;
        }
        if (w.hidden) continue;
        CGPoint windowPoint = [w convertPoint:point fromWindow:nil];
        UIView *hitView = [w hitTest:windowPoint withEvent:nil];
        if (hitView) {
            if ([hitView isKindOfClass:NSClassFromString(@"FlutterView")] || [hitView isKindOfClass:[UIWindow class]]) {
                continue;
            }
            [self triggerTapOnView:hitView atPoint:windowPoint];
            return;
        }
    }
    
    NSLog(@"[AutoClick] ❌ No view found to tap");
}

@end

// ============================================
// dylib 入口
// ============================================
__attribute__((constructor)) static void entry(void) {
    [AutoClickManager sharedManager];
}