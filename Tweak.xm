#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <dlfcn.h>
#import <objc/runtime.h>

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
static NSInteger gTargetViewIndex = 0;
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
        if (config[@"targetIndex"]) gTargetViewIndex = [config[@"targetIndex"] integerValue];
        NSLog(@"[AutoClick] 📂 Config loaded: click(%.0f,%.0f) float(%.0f,%.0f) targetIndex=%ld", gClickX, gClickY, gFloatX, gFloatY, (long)gTargetViewIndex);
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
        @"targetIndex": @(gTargetViewIndex)
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
// 设置页面 ViewController（只显示类名和坐标 x,y）
// ============================================
@interface AutoClickSettingsViewController : UIViewController <UITableViewDelegate, UITableViewDataSource, UITextFieldDelegate>
@property (nonatomic, strong) UITextField *xField;
@property (nonatomic, strong) UITextField *yField;
@property (nonatomic, strong) UILabel *floatPosLabel;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray *candidateViews;
@property (nonatomic, strong) NSMutableArray *viewDescriptions;
@property (nonatomic, assign) NSInteger selectedIndex;
@end

@implementation AutoClickSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    self.title = @"AutoClick 设置";
    self.selectedIndex = gTargetViewIndex;
    
    UIBarButtonItem *closeBtn = [[UIBarButtonItem alloc] initWithTitle:@"关闭" style:UIBarButtonItemStylePlain target:self action:@selector(close)];
    self.navigationItem.leftBarButtonItem = closeBtn;
    
    [self collectCandidateViews];
    
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
    _xField.delegate = self;
    [self.view addSubview:_xField];
    
    yOffset += height + 10;
    UILabel *yLabel = [[UILabel alloc] initWithFrame:CGRectMake(margin, yOffset, labelWidth, height)];
    yLabel.text = @"点击 Y:";
    [self.view addSubview:yLabel];
    _yField = [[UITextField alloc] initWithFrame:CGRectMake(margin + labelWidth + 10, yOffset, fieldWidth, height)];
    _yField.borderStyle = UITextBorderStyleRoundedRect;
    _yField.keyboardType = UIKeyboardTypeDecimalPad;
    _yField.text = [NSString stringWithFormat:@"%.0f", gClickY];
    _yField.delegate = self;
    [self.view addSubview:_yField];
    
    yOffset += height + 20;
    UIButton *saveBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    saveBtn.frame = CGRectMake(margin, yOffset, 100, 40);
    [saveBtn setTitle:@"保存" forState:UIControlStateNormal];
    [saveBtn addTarget:self action:@selector(save) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:saveBtn];
    
    yOffset += 60;
    UILabel *listLabel = [[UILabel alloc] initWithFrame:CGRectMake(margin, yOffset, 300, 30)];
    listLabel.text = @"选择目标视图 (点击选择):";
    listLabel.font = [UIFont systemFontOfSize:16];
    [self.view addSubview:listLabel];
    
    yOffset += 30;
    CGFloat tableHeight = self.view.bounds.size.height - yOffset - 20;
    _tableView = [[UITableView alloc] initWithFrame:CGRectMake(margin, yOffset, self.view.bounds.size.width - margin*2, tableHeight) style:UITableViewStylePlain];
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.rowHeight = 44;
    _tableView.backgroundColor = [UIColor whiteColor];
    [_tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"Cell"];
    [self.view addSubview:_tableView];
    
    yOffset = self.view.bounds.size.height - 60;
    _floatPosLabel = [[UILabel alloc] initWithFrame:CGRectMake(margin, yOffset, 300, 40)];
    _floatPosLabel.text = [NSString stringWithFormat:@"悬浮窗左上角: (%.0f, %.0f)", gFloatX, gFloatY];
    [self.view addSubview:_floatPosLabel];
}

- (void)collectCandidateViews {
    NSMutableArray *candidates = [NSMutableArray array];
    NSMutableArray *descriptions = [NSMutableArray array];
    CGRect screen = [UIScreen mainScreen].bounds;
    
    // 1. 先通过枚举收集候选视图（使用稳定的过滤条件）
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if ([NSStringFromClass([w class]) isEqualToString:@"AutoClickFloatingWindow"]) {
            continue;
        }
        if (w.hidden) continue;
        [self collectViews:w intoArray:candidates descriptions:descriptions screenBounds:screen];
    }
    
    // 2. 手动精确查找 FloatView（老贝贝图标）
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if ([NSStringFromClass([w class]) isEqualToString:@"AutoClickFloatingWindow"]) {
            continue;
        }
        if (w.hidden) continue;
        UIView *floatView = [self findFloatViewInView:w];
        if (floatView) {
            // 检查是否已在 candidates 中
            BOOL exists = NO;
            for (UIView *v in candidates) {
                if (v == floatView) {
                    exists = YES;
                    break;
                }
            }
            if (!exists) {
                [candidates addObject:floatView];
                CGRect frame = floatView.frame;
                [descriptions addObject:[NSString stringWithFormat:@"FloatView (%.0f,%.0f)", frame.origin.x, frame.origin.y]];
            }
        }
    }
    
    // 按坐标排序
    [candidates sortUsingComparator:^NSComparisonResult(id a, id b) {
        UIView *va = (UIView *)a;
        UIView *vb = (UIView *)b;
        CGRect ra = va.frame;
        CGRect rb = vb.frame;
        if (ra.origin.y < rb.origin.y) return NSOrderedAscending;
        if (ra.origin.y > rb.origin.y) return NSOrderedDescending;
        if (ra.origin.x < rb.origin.x) return NSOrderedAscending;
        if (ra.origin.x > rb.origin.x) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    
    self.candidateViews = candidates;
    self.viewDescriptions = descriptions;
    [self.tableView reloadData];
}

- (void)collectViews:(UIView *)view intoArray:(NSMutableArray *)candidates descriptions:(NSMutableArray *)descriptions screenBounds:(CGRect)screen {
    if (!view || view.hidden) return;
    CGRect frame = view.frame;
    CGFloat w = frame.size.width;
    CGFloat h = frame.size.height;
    BOOL inScreen = CGRectIntersectsRect(frame, screen) && !CGRectIsEmpty(frame);
    BOOL sizeOk = (w >= 20 && w <= 120 && h >= 20 && h <= 120);
    NSString *className = NSStringFromClass([view class]);
    // 只收集常见的悬浮图标类，避免 UIDimmingView 等
    BOOL isRelevant = [className rangeOfString:@"Float" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                      [className rangeOfString:@"Image" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                      [className rangeOfString:@"Button" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                      [className isEqualToString:@"UIView"];
    if (inScreen && sizeOk && isRelevant) {
        [candidates addObject:view];
        [descriptions addObject:[NSString stringWithFormat:@"%@ (%.0f,%.0f)", className, frame.origin.x, frame.origin.y]];
    }
    for (UIView *sub in view.subviews) {
        [self collectViews:sub intoArray:candidates descriptions:descriptions screenBounds:screen];
    }
}

// ---- 精确查找 FloatView ----
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

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    _floatPosLabel.text = [NSString stringWithFormat:@"悬浮窗左上角: (%.0f, %.0f)", gFloatX, gFloatY];
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
    gTargetViewIndex = self.selectedIndex;
    saveConfig();
    [self close];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

#pragma mark - TableView
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.candidateViews.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell" forIndexPath:indexPath];
    cell.textLabel.text = self.viewDescriptions[indexPath.row];
    cell.textLabel.font = [UIFont systemFontOfSize:14];
    cell.accessoryType = (indexPath.row == self.selectedIndex) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    self.selectedIndex = indexPath.row;
    [tableView reloadData];
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
- (void)collectViews:(UIView *)view intoArray:(NSMutableArray *)candidates;
- (UIView *)findFloatViewInView:(UIView *)view;
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

// ---- 触发点击：只触发手势，不模拟触摸 ----
- (void)triggerTapOnView:(UIView *)view {
    if (!view) return;
    BOOL hasTap = NO;
    for (UIGestureRecognizer *g in view.gestureRecognizers) {
        if ([g isKindOfClass:[UITapGestureRecognizer class]]) {
            hasTap = YES;
            break;
        }
    }
    if (!hasTap && ![view isKindOfClass:[UIControl class]]) {
        NSLog(@"[AutoClick] ⚠️ No tap gesture or UIControl on %@, skip", NSStringFromClass([view class]));
        return;
    }
    NSLog(@"[AutoClick] 🎯 Trying to trigger on %@", NSStringFromClass([view class]));
    
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
                                NSLog(@"[AutoClick] ✅ Gesture action triggered on %@", actionTarget);
                                return;
                            }
                        } @catch (NSException *e) {
                            NSLog(@"[AutoClick] ⚠️ Exception in gesture trigger: %@", e);
                        }
                    }
                }
            }
        }
    }
    if ([view isKindOfClass:[UIControl class]]) {
        @try {
            [(UIControl *)view sendActionsForControlEvents:UIControlEventTouchUpInside];
            NSLog(@"[AutoClick] ✅ UIControl action sent");
        } @catch (NSException *e) {
            NSLog(@"[AutoClick] ⚠️ Exception in UIControl: %@", e);
        }
    }
}

// ---- 点击入口 ----
- (void)performClick {
    CGPoint targetPoint = CGPointMake(gClickX, gClickY);
    NSLog(@"[AutoClick] 🚀 Perform click at (%.0f, %.0f)", targetPoint.x, targetPoint.y);
    showTapMarkerAtPoint(targetPoint);
    
    NSInteger index = gTargetViewIndex;
    NSMutableArray *candidates = [NSMutableArray array];
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if ([NSStringFromClass([w class]) isEqualToString:@"AutoClickFloatingWindow"]) {
            continue;
        }
        if (w.hidden) continue;
        [self collectViews:w intoArray:candidates];
    }
    // 额外手动查找 FloatView（确保不遗漏）
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if ([NSStringFromClass([w class]) isEqualToString:@"AutoClickFloatingWindow"]) {
            continue;
        }
        if (w.hidden) continue;
        UIView *floatView = [self findFloatViewInView:w];
        if (floatView) {
            BOOL exists = NO;
            for (UIView *v in candidates) {
                if (v == floatView) {
                    exists = YES;
                    break;
                }
            }
            if (!exists) {
                [candidates addObject:floatView];
            }
        }
    }
    
    if (index >= 0 && index < candidates.count) {
        UIView *targetView = candidates[index];
        [self triggerTapOnView:targetView];
    } else {
        NSLog(@"[AutoClick] ❌ Invalid target index %ld", (long)index);
    }
}

// ---- 收集视图（与设置界面一致，过滤条件相同） ----
- (void)collectViews:(UIView *)view intoArray:(NSMutableArray *)candidates {
    if (!view || view.hidden) return;
    CGRect frame = view.frame;
    CGFloat w = frame.size.width;
    CGFloat h = frame.size.height;
    BOOL sizeOk = (w >= 20 && w <= 120 && h >= 20 && h <= 120);
    NSString *className = NSStringFromClass([view class]);
    BOOL isRelevant = [className rangeOfString:@"Float" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                      [className rangeOfString:@"Image" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                      [className rangeOfString:@"Button" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                      [className isEqualToString:@"UIView"];
    if (sizeOk && isRelevant) {
        [candidates addObject:view];
    }
    for (UIView *sub in view.subviews) {
        [self collectViews:sub intoArray:candidates];
    }
}

// ---- 精确查找 FloatView ----
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

@end

// ============================================
// dylib 入口
// ============================================
__attribute__((constructor)) static void entry(void) {
    [AutoClickManager sharedManager];
}