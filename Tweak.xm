#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <dlfcn.h>
#import <objc/message.h>

// ============================================
// 1. GSEvent 私有 API（模拟点击）
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
    }
}

static void simulateTapAtPoint(CGPoint point) {
    if (!GSEventRecordCreate || !GSEventDispatch) {
        NSLog(@"[AutoClick] GSEvent functions not available");
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
}

// ============================================
// 2. 配置管理（读写 plist）
// ============================================
static NSString *const kConfigFileName = @"autoclick_config.plist";

static CGFloat gClickX = 100.0;
static CGFloat gClickY = 100.0;
static CGFloat gFloatX = 100.0;   // 悬浮窗左上角 X
static CGFloat gFloatY = 100.0;   // 悬浮窗左上角 Y
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
    // 边界保护
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
// 3. 自定义 UIWindow（让事件穿透）
// ============================================
@interface AutoClickFloatingWindow : UIWindow
@end

@implementation AutoClickFloatingWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    // 如果点击到了自己或根视图，但实际子视图未响应，则穿透
    if (hitView == self || hitView == self.rootViewController.view) {
        // 检查是否点到了悬浮窗的子视图
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
// 4. 设置页面 ViewController
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

    // 关闭按钮
    UIBarButtonItem *closeBtn = [[UIBarButtonItem alloc] initWithTitle:@"关闭" style:UIBarButtonItemStylePlain target:self action:@selector(close)];
    self.navigationItem.leftBarButtonItem = closeBtn;

    CGFloat margin = 20;
    CGFloat yOffset = 100;
    CGFloat labelWidth = 80;
    CGFloat fieldWidth = 120;
    CGFloat height = 40;

    // X 坐标
    UILabel *xLabel = [[UILabel alloc] initWithFrame:CGRectMake(margin, yOffset, labelWidth, height)];
    xLabel.text = @"点击 X:";
    [self.view addSubview:xLabel];

    _xField = [[UITextField alloc] initWithFrame:CGRectMake(margin + labelWidth + 10, yOffset, fieldWidth, height)];
    _xField.borderStyle = UITextBorderStyleRoundedRect;
    _xField.keyboardType = UIKeyboardTypeDecimalPad;
    _xField.text = [NSString stringWithFormat:@"%.0f", gClickX];
    _xField.delegate = self;
    [self.view addSubview:_xField];

    // Y 坐标
    yOffset += height + 20;
    UILabel *yLabel = [[UILabel alloc] initWithFrame:CGRectMake(margin, yOffset, labelWidth, height)];
    yLabel.text = @"点击 Y:";
    [self.view addSubview:yLabel];

    _yField = [[UITextField alloc] initWithFrame:CGRectMake(margin + labelWidth + 10, yOffset, fieldWidth, height)];
    _yField.borderStyle = UITextBorderStyleRoundedRect;
    _yField.keyboardType = UIKeyboardTypeDecimalPad;
    _yField.text = [NSString stringWithFormat:@"%.0f", gClickY];
    _yField.delegate = self;
    [self.view addSubview:_yField];

    // 保存按钮
    yOffset += height + 30;
    UIButton *saveBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    saveBtn.frame = CGRectMake(margin, yOffset, 100, 40);
    [saveBtn setTitle:@"保存" forState:UIControlStateNormal];
    [saveBtn addTarget:self action:@selector(save) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:saveBtn];

    // 悬浮窗位置信息
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
    // 更新悬浮窗坐标
    _floatPosLabel.text = [NSString stringWithFormat:@"(%.0f, %.0f)", gFloatX, gFloatY];
}

- (void)close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)save {
    CGFloat x = [_xField.text doubleValue];
    CGFloat y = [_yField.text doubleValue];
    CGRect screen = [UIScreen mainScreen].bounds;
    if (x < 0 || x > screen.size.width || y < 0 || y > screen.size.height) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"坐标无效"
                                                                       message:@"请输入屏幕范围内的坐标"
                                                                preferredStyle:UIAlertControllerStyleAlert];
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
// 5. 悬浮窗视图（可拖动、长按弹出设置）
// ============================================
@interface AutoClickFloatingView : UIView
@property (nonatomic, weak) id target;
@property (nonatomic, assign) SEL action;
@end

@implementation AutoClickFloatingView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];

        // 圆形按钮
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.frame = self.bounds;
        btn.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:0.85];
        btn.layer.cornerRadius = frame.size.width / 2;
        btn.clipsToBounds = YES;
        [btn setTitle:@"▶" forState:UIControlStateNormal];
        [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont boldSystemFontOfSize:22];
        [btn addTarget:self action:@selector(buttonTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:btn];

        // 长按手势 → 弹出设置
        UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPress:)];
        [self addGestureRecognizer:longPress];

        // 拖动手势
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
    } else {
        NSLog(@"[AutoClick] 悬浮窗点击但未设置 target/action");
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
    UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
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
// 6. 主管理器（负责创建悬浮窗和执行点击）
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
        // 延迟1秒后显示悬浮窗，确保 App 界面已经加载
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
    NSLog(@"[AutoClick] 点击坐标: (%.0f, %.0f)", gClickX, gClickY);
    simulateTapAtPoint(CGPointMake(gClickX, gClickY));
}

@end

// ============================================
// 7. dylib 入口
// ============================================
__attribute__((constructor)) static void entry(void) {
    initGSEvent();
    [AutoClickManager sharedManager];
}