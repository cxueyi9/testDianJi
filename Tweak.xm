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
// 标记点击位置（红色圆点）
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

// ---- 收集候选视图（按距离排序，只保留最近的 10 个） ----
- (void)collectCandidateViews:(NSMutableArray *)candidates {
    CGPoint target = CGPointMake(gClickX, gClickY);
    NSMutableArray *allViews = [NSMutableArray array];
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if ([NSStringFromClass([w class]) isEqualToString:@"AutoClickFloatingWindow"]) {
            continue;
        }
        if (w.hidden) continue;
        [self collectAllViews:w intoArray:allViews];
    }
    // 计算距离并排序
    [allViews sortUsingComparator:^NSComparisonResult(id a, id b) {
        UIView *va = (UIView *)a;
        UIView *vb = (UIView *)b;
        CGPoint ca = [va convertPoint:CGPointMake(CGRectGetMidX(va.bounds), CGRectGetMidY(va.bounds)) toView:nil];
        CGPoint cb = [vb convertPoint:CGPointMake(CGRectGetMidX(vb.bounds), CGRectGetMidY(vb.bounds)) toView:nil];
        CGFloat da = hypot(ca.x - target.x, ca.y - target.y);
        CGFloat db = hypot(cb.x - target.x, cb.y - target.y);
        if (da < db) return NSOrderedAscending;
        if (da > db) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    // 只取前 10 个（避免列表过长）
    NSInteger maxCount = MIN(10, allViews.count);
    for (NSInteger i = 0; i < maxCount; i++) {
        [candidates addObject:allViews[i]];
    }
}

- (void)collectAllViews:(UIView *)view intoArray:(NSMutableArray *)array {
    if (!view || view.hidden) return;
    // 只收集大小在 20~120 之间的视图（排除太小或太大的）
    CGRect frame = view.frame;
    CGFloat w = frame.size.width;
    CGFloat h = frame.size.height;
    if (w >= 20 && w <= 120 && h >= 20 && h <= 120) {
        [array addObject:view];
    }
    for (UIView *sub in view.subviews) {
        [self collectAllViews:sub intoArray:array];
    }
}

- (void)selectTarget {
    NSMutableArray *candidates = [NSMutableArray array];
    [self collectCandidateViews:candidates];
    
    if (candidates.count == 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示" message:@"未找到任何候选视图" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    NSMutableArray *titles = [NSMutableArray array];
    for (NSInteger i = 0; i < candidates.count; i++) {
        UIView *v = candidates[i];
        CGPoint center = [v convertPoint:CGPointMake(CGRectGetMidX(v.bounds), CGRectGetMidY(v.bounds)) toView:nil];
        [titles addObject:[NSString stringWithFormat:@"%ld: %@ (%.0f,%.0f)", (long)i, NSStringFromClass([v class]), center.x, center.y]];
    }
    
    UIAlertController *actionSheet = [UIAlertController alertControllerWithTitle:@"选择点击目标" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSInteger i = 0; i < titles.count; i++) {
        NSString *title = titles[i];
        [actionSheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            gSelectedIndex = i;
            saveConfig();
            [self updateSelectedLabel];
            NSLog(@"[AutoClick] ✅ Selected view index: %ld", (long)i);
        }]];
    }
    [actionSheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:actionSheet animated:YES completion:nil];
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
- (void)triggerTapOnView:(UIView *)view;
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

// ---- 🔥 关键方法：只触发手势，不模拟触摸 ----
- (void)triggerTapOnView:(UIView *)view {
    if (!view) return;
    NSLog(@"[AutoClick] 🎯 Trying to trigger on %@", NSStringFromClass([view class]));
    
    // 先尝试无参数手势
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
                            // 尝试带参数
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
    
    // 如果都没有手势，不执行任何操作
    NSLog(@"[AutoClick] ⚠️ No tap gesture found on %@, abort", NSStringFromClass([view class]));
}

// ---- 点击入口 ----
- (void)performClick {
    CGPoint targetPoint = CGPointMake(gClickX, gClickY);
    NSLog(@"[AutoClick] 🚀 Perform click at (%.0f, %.0f)", targetPoint.x, targetPoint.y);
    showTapMarkerAtPoint(targetPoint);
    
    // 收集候选视图（与设置界面一致）
    NSMutableArray *candidates = [NSMutableArray array];
    CGPoint target = CGPointMake(gClickX, gClickY);
    NSMutableArray *allViews = [NSMutableArray array];
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if ([NSStringFromClass([w class]) isEqualToString:@"AutoClickFloatingWindow"]) {
            continue;
        }
        if (w.hidden) continue;
        [self collectAllViews:w intoArray:allViews];
    }
    // 按距离排序
    [allViews sortUsingComparator:^NSComparisonResult(id a, id b) {
        UIView *va = (UIView *)a;
        UIView *vb = (UIView *)b;
        CGPoint ca = [va convertPoint:CGPointMake(CGRectGetMidX(va.bounds), CGRectGetMidY(va.bounds)) toView:nil];
        CGPoint cb = [vb convertPoint:CGPointMake(CGRectGetMidX(vb.bounds), CGRectGetMidY(vb.bounds)) toView:nil];
        CGFloat da = hypot(ca.x - target.x, ca.y - target.y);
        CGFloat db = hypot(cb.x - target.x, cb.y - target.y);
        if (da < db) return NSOrderedAscending;
        if (da > db) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    NSInteger maxCount = MIN(10, allViews.count);
    for (NSInteger i = 0; i < maxCount; i++) {
        [candidates addObject:allViews[i]];
    }
    
    if (candidates.count == 0) {
        NSLog(@"[AutoClick] ❌ No candidate views found");
        return;
    }
    
    if (gSelectedIndex >= candidates.count) {
        gSelectedIndex = 0;
        saveConfig();
    }
    
    UIView *target = candidates[gSelectedIndex];
    NSLog(@"[AutoClick] 🎯 Using candidate index %ld: %@ at (%.0f,%.0f)", (long)gSelectedIndex, NSStringFromClass([target class]), targetPoint.x, targetPoint.y);
    [self triggerTapOnView:target];
}

- (void)collectAllViews:(UIView *)view intoArray:(NSMutableArray *)array {
    if (!view || view.hidden) return;
    CGRect frame = view.frame;
    CGFloat w = frame.size.width;
    CGFloat h = frame.size.height;
    if (w >= 20 && w <= 120 && h >= 20 && h <= 120) {
        [array addObject:view];
    }
    for (UIView *sub in view.subviews) {
        [self collectAllViews:sub intoArray:array];
    }
}

@end

// ============================================
// dylib 入口
// ============================================
__attribute__((constructor)) static void entry(void) {
    [AutoClickManager sharedManager];
}