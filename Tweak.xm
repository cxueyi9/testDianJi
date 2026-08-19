#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <dlfcn.h>
#import <objc/message.h>
#import "PTFakeMetaTouch.h"
#import "UITouch-KIFAdditions.h"

// ============================================
// 辅助函数：获取当前 key window（暂未使用，但保留）
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
// GSEvent 备用（可选项，保留但可能不使用）
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
static void simulateTapWithGSEvent(CGPoint point) {
    if (!GSEventRecordCreate || !GSEventDispatch) {
        NSLog(@"[AutoClick] ⚠️ GSEvent not available, skip");
        return;
    }
    GSEventRef down1 = GSEventRecordCreate(kGSEventTypeTouchDown, 0, point, 0, 0, 0);
    if (down1) GSEventDispatch(down1);
    GSEventRef up1 = GSEventRecordCreate(kGSEventTypeTouchUp, 0, point, 0, 0, 0);
    if (up1) GSEventDispatch(up1);
    NSLog(@"[AutoClick] 👆 GSEvent tap (no path)");
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
- (void)printViewHierarchy:(UIView *)view depth:(int)depth;
- (void)simulateTapOnImageView:(UIView *)imageView;
- (void)simulateFlutterTouchAtPoint:(CGPoint)point onView:(UIView *)flutterView;
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
        initGSEvent();
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

// ============================================
// 核心点击方法
// ============================================
- (void)performClick {
    CGPoint point = CGPointMake(gClickX, gClickY);
    NSLog(@"[AutoClick] 🚀 Perform click at (%.0f, %.0f)", point.x, point.y);
    
    showTapMarkerAtPoint(point);
    
    // ---- 遍历所有窗口执行 hitTest ----
    UIView *hitView = nil;
    UIWindow *hitWindow = nil;
    CGPoint hitPoint = CGPointZero;

    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if ([NSStringFromClass([w class]) isEqualToString:@"AutoClickFloatingWindow"]) {
            continue;
        }
        if (w.hidden || !w.rootViewController) {
            continue;
        }
        CGPoint windowPoint = [w convertPoint:point fromWindow:nil];
        UIView *view = [w hitTest:windowPoint withEvent:nil];
        if (view) {
            hitView = view;
            hitWindow = w;
            hitPoint = windowPoint;
            break;
        }
    }

    if (!hitView) {
        NSLog(@"[AutoClick] ❌ No view at point in any window");
        return;
    }

    NSLog(@"[AutoClick] 🎯 Found view: %@ in window: %@ at point: (%.0f,%.0f)", 
          NSStringFromClass([hitView class]), 
          NSStringFromClass([hitWindow class]), 
          hitPoint.x, hitPoint.y);

    // ---- 打印视图层级 ----
    [self printViewHierarchy:hitView depth:0];

    // ---- 根据视图类型选择模拟方式 ----
    if ([hitView isKindOfClass:[UIImageView class]]) {
        NSLog(@"[AutoClick] 🎯 UIImageView detected");
        [self simulateTapOnImageView:hitView];
        return;
    }

if ([hitView isKindOfClass:NSClassFromString(@"FlutterView")]) {
    [self simulateFlutterTouchAtPoint:hitPoint onView:hitView inWindow:hitWindow];
    return;
}

    // ---- 常规 UIKit 处理 ----
    UITouch *touch = [[UITouch alloc] initAtPoint:hitPoint inView:hitView];
    [hitView touchesBegan:[NSSet setWithObject:touch] withEvent:nil];
    [hitView touchesEnded:[NSSet setWithObject:touch] withEvent:nil];
    NSLog(@"[AutoClick] ✅ Direct touchesBegan/Ended sent");

    // PTFakeTouch 备用
    NSInteger pointId = [PTFakeMetaTouch fakeTouchId:0 AtPoint:point withTouchPhase:UITouchPhaseBegan];
    if (pointId > 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.05 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [PTFakeMetaTouch fakeTouchId:pointId AtPoint:point withTouchPhase:UITouchPhaseEnded];
        });
    }
}

// ============================================
// 辅助方法：打印视图层级
// ============================================
- (void)printViewHierarchy:(UIView *)view depth:(int)depth {
    if (!view) return;
    NSMutableString *indent = [NSMutableString string];
    for (int i = 0; i < depth; i++) [indent appendString:@"  "];
    NSLog(@"[AutoClick] %@%@ frame:%@", indent, NSStringFromClass([view class]), NSStringFromCGRect(view.frame));
    for (UIView *sub in view.subviews) {
        [self printViewHierarchy:sub depth:depth+1];
    }
}

// ============================================
// 模拟点击 UIImageView（通过手势识别器）
// ============================================
- (void)simulateTapOnImageView:(UIView *)imageView inWindow:(UIWindow *)window {
    // 通过目标窗口发送触摸事件
    UITouch *touch = [[UITouch alloc] initAtPoint:imageView.center inView:imageView];
    [touch setPhaseAndUpdateTimestamp:UITouchPhaseBegan];
    UIEvent *event = [self eventWithTouches:@[touch] inWindow:window];
    [window sendEvent:event];
    
    [touch setPhaseAndUpdateTimestamp:UITouchPhaseEnded];
    event = [self eventWithTouches:@[touch] inWindow:window];
    [window sendEvent:event];
}

// ============================================
// 模拟点击 FlutterView
// ============================================
- (void)simulateFlutterTouchAtPoint:(CGPoint)point onView:(UIView *)flutterView inWindow:(UIWindow *)window {
    // 构造 UITouch 并发送到 FlutterView
    UITouch *touch = [[UITouch alloc] initAtPoint:point inView:flutterView];
    [touch setPhaseAndUpdateTimestamp:UITouchPhaseBegan];
    UIEvent *event = [self eventWithTouches:@[touch] inWindow:window];
    [window sendEvent:event];
    
    // 发送抬起事件
    [touch setPhaseAndUpdateTimestamp:UITouchPhaseEnded];
    event = [self eventWithTouches:@[touch] inWindow:window];
    [window sendEvent:event];
    
    NSLog(@"[AutoClick] ✅ FlutterView touches sent via target window");
}

- (UIEvent *)eventWithTouches:(NSArray *)touches inWindow:(UIWindow *)window {
    // 使用 UIApplication 的私有方法 _touchesEvent 创建事件
    UIEvent *event = [[UIApplication sharedApplication] _touchesEvent];
    [event _clearTouches];
    [event kif_setEventWithTouches:touches];
    for (UITouch *touch in touches) {
        [event _addTouch:touch forDelayedDelivery:NO];
    }
    return event;
}

@end

// ============================================
// dylib 入口
// ============================================
__attribute__((constructor)) static void entry(void) {
    [AutoClickManager sharedManager];
}