#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import "PTFakeMetaTouch.h"
#import "UITouch-KIFAdditions.h"
#import "UIApplication-KIFAdditions.h"
#import "UIEvent+KIFAdditions.h"

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
static CGFloat gClickX = 390.0;
static CGFloat gClickY = 400.0;
static CGFloat gFloatX = 100.0;
static CGFloat gFloatY = 100.0;
static NSInteger gSelectedIndex = 0;
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
        if (config[@"selectedIndex"]) gSelectedIndex = [config[@"selectedIndex"] integerValue];
        NSLog(@"[AutoClick] 📂 Config loaded: click(%.0f,%.0f) float(%.0f,%.0f) index:%ld", gClickX, gClickY, gFloatX, gFloatY, (long)gSelectedIndex);
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
        @"floatY": @(gFloatY),
        @"selectedIndex": @(gSelectedIndex)
    };
    NSString *docPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *configPath = [docPath stringByAppendingPathComponent:kConfigFileName];
    [config writeToFile:configPath atomically:YES];
    NSLog(@"[AutoClick] 💾 Config saved");
}

// ============================================
// 标记点击位置（红色圆点）- 添加到悬浮窗上层
// ============================================
static void showTapMarkerAtPoint(CGPoint point) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *targetWindow = nil;
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            if ([NSStringFromClass([w class]) isEqualToString:@"AutoClickFloatingWindow"]) {
                targetWindow = w;
                break;
            }
        }
        if (!targetWindow) {
            targetWindow = GetKeyWindow();
        }
        if (!targetWindow) return;
        
        UIView *oldMarker = [targetWindow viewWithTag:9999];
        if (oldMarker) [oldMarker removeFromSuperview];
        
        UIView *marker = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 30, 30)];
        marker.center = point;
        marker.backgroundColor = [UIColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:0.9];
        marker.layer.cornerRadius = 15;
        marker.layer.borderWidth = 3;
        marker.layer.borderColor = [UIColor yellowColor].CGColor;
        marker.userInteractionEnabled = NO;
        marker.tag = 9999;
        [targetWindow addSubview:marker];
        NSLog(@"[AutoClick] 🔴 Marker at (%.0f,%.0f) on window: %@", point.x, point.y, NSStringFromClass([targetWindow class]));
        
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
@property (nonatomic, strong) UIButton *selectTargetBtn;
@property (nonatomic, strong) UILabel *selectedLabel;
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
    [saveBtn setTitle:@"保存坐标" forState:UIControlStateNormal];
    [saveBtn addTarget:self action:@selector(save) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:saveBtn];

    yOffset += height + 20;
    _selectTargetBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    _selectTargetBtn.frame = CGRectMake(margin, yOffset, 200, 40);
    [_selectTargetBtn setTitle:@"选择点击目标" forState:UIControlStateNormal];
    [_selectTargetBtn addTarget:self action:@selector(selectTarget) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_selectTargetBtn];

    yOffset += height + 10;
    _selectedLabel = [[UILabel alloc] initWithFrame:CGRectMake(margin, yOffset, 300, 30)];
    _selectedLabel.textColor = [UIColor darkGrayColor];
    _selectedLabel.font = [UIFont systemFontOfSize:14];
    [self.view addSubview:_selectedLabel];
    [self updateSelectedLabel];

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
    [self updateSelectedLabel];
}

- (void)updateSelectedLabel {
    _selectedLabel.text = [NSString stringWithFormat:@"当前选择目标索引: %ld", (long)gSelectedIndex];
}

- (void)selectTarget {
    // 收集候选视图（包含所有可能被点击的视图，通过 hitTest 或递归收集）
    NSMutableArray *candidates = [NSMutableArray array];
    NSMutableArray *descriptions = [NSMutableArray array];
    CGRect screen = [UIScreen mainScreen].bounds;
    
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if ([NSStringFromClass([w class]) isEqualToString:@"AutoClickFloatingWindow"]) {
            continue;
        }
        if (w.hidden) continue;
        [self collectCandidateViews:w intoArray:candidates descriptions:descriptions screenBounds:screen];
    }
    
    if (candidates.count == 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示" message:@"未找到任何可点击视图" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    // 构建选择列表
    UIAlertController *actionSheet = [UIAlertController alertControllerWithTitle:@"选择点击目标" message:@"点击选择要模拟点击的视图" preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSInteger i = 0; i < candidates.count; i++) {
        UIView *v = candidates[i];
        CGPoint center = [v convertPoint:CGPointMake(CGRectGetMidX(v.bounds), CGRectGetMidY(v.bounds)) toView:nil];
        NSString *className = NSStringFromClass([v class]);
        NSString *title = [NSString stringWithFormat:@"%ld: %@ (%.0f,%.0f)", (long)i, className, center.x, center.y];
        [actionSheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            gSelectedIndex = i;
            saveConfig();
            [self updateSelectedLabel];
            NSLog(@"[AutoClick] ✅ Selected candidate index: %ld", (long)i);
        }]];
    }
    [actionSheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:actionSheet animated:YES completion:nil];
}

- (void)collectCandidateViews:(UIView *)view intoArray:(NSMutableArray *)candidates descriptions:(NSMutableArray *)descriptions screenBounds:(CGRect)screen {
    if (!view || view.hidden) return;
    CGRect frame = view.frame;
    CGFloat w = frame.size.width;
    CGFloat h = frame.size.height;
    BOOL inScreen = CGRectIntersectsRect(frame, screen) && !CGRectIsEmpty(frame);
    BOOL sizeOk = (w >= 20 && w <= 120 && h >= 20 && h <= 120);
    NSString *className = NSStringFromClass([view class]);
    // 收集类名包含 Float, Image, Button 或 UIView 的视图，且交互性检查（有手势或 UIControl）
    BOOL isInteractive = NO;
    for (UIGestureRecognizer *g in view.gestureRecognizers) {
        if ([g isKindOfClass:[UITapGestureRecognizer class]]) { isInteractive = YES; break; }
    }
    if ([view isKindOfClass:[UIControl class]]) isInteractive = YES;
    BOOL isRelevant = [className rangeOfString:@"Float" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                      [className rangeOfString:@"Image" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                      [className rangeOfString:@"Button" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                      [className isEqualToString:@"UIView"] ||
                      [className isEqualToString:@"FloatView"];
    if (inScreen && sizeOk && isRelevant && isInteractive) {
        [candidates addObject:view];
        [descriptions addObject:[NSString stringWithFormat:@"%@ (%.0f,%.0f)", className, frame.origin.x, frame.origin.y]];
    }
    for (UIView *sub in view.subviews) {
        [self collectCandidateViews:sub intoArray:candidates descriptions:descriptions screenBounds:screen];
    }
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
- (void)collectCandidateViews:(UIView *)view intoArray:(NSMutableArray *)candidates;
- (void)sendTapAtPoint:(CGPoint)screenPoint inWindow:(UIWindow *)window withDuration:(NSTimeInterval)duration;
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

// ---- 收集候选视图（与设置界面一致） ----
- (void)collectCandidateViews:(UIView *)view intoArray:(NSMutableArray *)candidates {
    if (!view || view.hidden) return;
    CGRect frame = view.frame;
    CGFloat w = frame.size.width;
    CGFloat h = frame.size.height;
    BOOL sizeOk = (w >= 20 && w <= 120 && h >= 20 && h <= 120);
    NSString *className = NSStringFromClass([view class]);
    BOOL isInteractive = NO;
    for (UIGestureRecognizer *g in view.gestureRecognizers) {
        if ([g isKindOfClass:[UITapGestureRecognizer class]]) { isInteractive = YES; break; }
    }
    if ([view isKindOfClass:[UIControl class]]) isInteractive = YES;
    BOOL isRelevant = [className rangeOfString:@"Float" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                      [className rangeOfString:@"Image" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                      [className rangeOfString:@"Button" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                      [className isEqualToString:@"UIView"] ||
                      [className isEqualToString:@"FloatView"];
    if (sizeOk && isRelevant && isInteractive) {
        [candidates addObject:view];
    }
    for (UIView *sub in view.subviews) {
        [self collectCandidateViews:sub intoArray:candidates];
    }
}

// ---- 发送触摸事件 ----
- (void)sendTapAtPoint:(CGPoint)screenPoint inWindow:(UIWindow *)window withDuration:(NSTimeInterval)duration {
    if (!window) {
        NSLog(@"[AutoClick] ❌ Window is nil");
        return;
    }
    CGPoint windowPoint = [window convertPoint:screenPoint fromWindow:nil];
    NSLog(@"[AutoClick] 📱 Sending touch at screen(%.0f,%.0f) -> window(%.0f,%.0f) duration %.2f", screenPoint.x, screenPoint.y, windowPoint.x, windowPoint.y, duration);
    
    @try {
        UITouch *touch = [[UITouch alloc] initAtPoint:windowPoint inWindow:window];
        if (!touch) { return; }
        [touch setPhaseAndUpdateTimestamp:UITouchPhaseBegan];
        [touch setTapCount:1];
        
        UIEvent *event = [[UIApplication sharedApplication] _touchesEvent];
        [event _clearTouches];
        [event kif_setEventWithTouches:@[touch]];
        [event _addTouch:touch forDelayedDelivery:NO];
        [[UIApplication sharedApplication] sendEvent:event];
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [touch setPhaseAndUpdateTimestamp:UITouchPhaseEnded];
            [event _clearTouches];
            [event kif_setEventWithTouches:@[touch]];
            [event _addTouch:touch forDelayedDelivery:NO];
            [[UIApplication sharedApplication] sendEvent:event];
            NSLog(@"[AutoClick] ✅ Touch ended");
        });
    } @catch (NSException *e) {
        NSLog(@"[AutoClick] ❌ Exception in sendTapAtPoint: %@", e);
    }
}

// ---- 触发点击（合并版本二的正确方法） ----
- (void)triggerTapOnView:(UIView *)view atPoint:(CGPoint)point {
    if (!view) return;
    NSLog(@"[AutoClick] 🎯 Trying to trigger on %@ at point (%.0f,%.0f)", NSStringFromClass([view class]), point.x, point.y);
    
    // 先尝试手势（无参数）
    for (UIGestureRecognizer *g in view.gestureRecognizers) {
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
                                [actionTarget performSelector:action];
                                #pragma clang diagnostic pop
                                NSLog(@"[AutoClick] ✅ Gesture action triggered (no params) on %@", actionTarget);
                                return;
                            }
                        } @catch (NSException *e) {
                            @try {
                                if ([actionTarget respondsToSelector:action]) {
                                    #pragma clang diagnostic push
                                    #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                                    [actionTarget performSelector:action withObject:g];
                                    #pragma clang diagnostic pop
                                    NSLog(@"[AutoClick] ✅ Gesture action triggered (with gesture) on %@", actionTarget);
                                    return;
                                }
                            } @catch (NSException *e2) {
                                NSLog(@"[AutoClick] ❌ Exception: %@", e2);
                            }
                        }
                    }
                }
            }
        }
    }
    
    // 如果是 UIControl
    if ([view isKindOfClass:[UIControl class]]) {
        @try {
            [(UIControl *)view sendActionsForControlEvents:UIControlEventTouchUpInside];
            NSLog(@"[AutoClick] ✅ UIControl action sent");
            return;
        } @catch (NSException *e) {
            NSLog(@"[AutoClick] ⚠️ UIControl exception: %@", e);
        }
    }
    
    // 获取视图所在的窗口
    UIWindow *window = view.window;
    if (!window) {
        NSLog(@"[AutoClick] ❌ View has no window");
        return;
    }
    
    // point 已经是屏幕坐标，直接使用
    NSLog(@"[AutoClick] 📐 Using screen point directly: (%.0f,%.0f)", point.x, point.y);
    
    // 只发送短按 (0.2秒)
    [self sendTapAtPoint:point inWindow:window withDuration:0.2];
}

// ---- 点击入口 ----
- (void)performClick {
    CGPoint targetPoint = CGPointMake(gClickX, gClickY);
    NSLog(@"[AutoClick] 🚀 Perform click at (%.0f, %.0f)", targetPoint.x, targetPoint.y);
    showTapMarkerAtPoint(targetPoint);
    
    // 收集候选视图
    NSMutableArray *candidates = [NSMutableArray array];
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if ([NSStringFromClass([w class]) isEqualToString:@"AutoClickFloatingWindow"]) {
            continue;
        }
        if (w.hidden) continue;
        [self collectCandidateViews:w intoArray:candidates];
    }
    
    if (candidates.count == 0) {
        NSLog(@"[AutoClick] ❌ No candidate views found");
        return;
    }
    
    // 确保索引有效
    if (gSelectedIndex >= candidates.count) {
        gSelectedIndex = 0;
        saveConfig();
    }
    
    UIView *target = candidates[gSelectedIndex];
    CGPoint center = CGPointMake(CGRectGetMidX(target.bounds), CGRectGetMidY(target.bounds));
    CGPoint screenCenter = [target convertPoint:center toView:nil];
    NSLog(@"[AutoClick] 🎯 Using candidate index %ld at screen center (%.0f,%.0f)", (long)gSelectedIndex, screenCenter.x, screenCenter.y);
    
    // 使用正确的触发方法
    [self triggerTapOnView:target atPoint:screenCenter];
}

@end

// ============================================
// dylib 入口
// ============================================
__attribute__((constructor)) static void entry(void) {
    [AutoClickManager sharedManager];
}