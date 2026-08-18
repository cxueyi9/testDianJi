#import <UIKit/UIKit.h>
#import <dispatch/dispatch.h>
#import <dlfcn.h>
#import <objc/message.h>

// ===== GSEvent 私有 API 声明 =====
typedef struct __GSEvent *GSEventRef;
typedef enum {
    kGSEventTypeTouchDown = 1,
    kGSEventTypeTouchUp   = 2,
    kGSEventTypeTouchMoved = 3,
} GSEventType;

typedef enum {
    kGSEventSubTypeUnknown = 0,
} GSEventSubType;

typedef GSEventRef (*GSEventRecordCreateFunc)(GSEventType type, GSEventSubType subtype, CGPoint location, int unknown1, int unknown2, int unknown3);
typedef void (*GSEventRecordSetPathInfoFunc)(GSEventRef event, CFArrayRef pathInfo);
typedef void (*GSEventDispatchFunc)(GSEventRef event);

static GSEventRecordCreateFunc      GSEventRecordCreate     = NULL;
static GSEventRecordSetPathInfoFunc GSEventRecordSetPathInfo = NULL;
static GSEventDispatchFunc          GSEventDispatch         = NULL;

// ===== 配置参数 =====
static CGFloat   gDelay   = 5.0;        // 默认 5 秒
static CGPoint   gTapPoint = CGPointMake(100, 100); // 默认坐标

// ===== 加载 GSEvent 函数 =====
static void initGSEvent(void) {
    void *handle = dlopen("/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices", RTLD_LAZY);
    if (handle) {
        GSEventRecordCreate      = (GSEventRecordCreateFunc)dlsym(handle, "GSEventRecordCreate");
        GSEventRecordSetPathInfo = (GSEventRecordSetPathInfoFunc)dlsym(handle, "GSEventRecordSetPathInfo");
        GSEventDispatch          = (GSEventDispatchFunc)dlsym(handle, "GSEventDispatch");
    }
}

// ===== 模拟点击坐标 =====
static void simulateTapAtPoint(CGPoint point) {
    if (!GSEventRecordCreate || !GSEventDispatch) {
        NSLog(@"[AutoClick] GSEvent functions not available");
        return;
    }

    // 1. 按下事件
    GSEventRef down = GSEventRecordCreate(kGSEventTypeTouchDown, kGSEventSubTypeUnknown, point, 0, 0, 0);
    if (down) {
        if (GSEventRecordSetPathInfo) {
            // 设置路径信息（空数组即可）
            CFArrayRef emptyPath = CFArrayCreate(NULL, NULL, 0, &kCFTypeArrayCallBacks);
            GSEventRecordSetPathInfo(down, emptyPath);
            CFRelease(emptyPath);
        }
        GSEventDispatch(down);
    }

    // 2. 抬起事件
    GSEventRef up = GSEventRecordCreate(kGSEventTypeTouchUp, kGSEventSubTypeUnknown, point, 0, 0, 0);
    if (up) {
        if (GSEventRecordSetPathInfo) {
            CFArrayRef emptyPath = CFArrayCreate(NULL, NULL, 0, &kCFTypeArrayCallBacks);
            GSEventRecordSetPathInfo(up, emptyPath);
            CFRelease(emptyPath);
        }
        GSEventDispatch(up);
    }
}

// ===== 从配置文件加载参数 =====
static void loadConfig(void) {
    NSString *docPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *configPath = [docPath stringByAppendingPathComponent:@"autoclick_config.plist"];
    NSDictionary *config = [NSDictionary dictionaryWithContentsOfFile:configPath];

    if (config) {
        NSNumber *delayNum = config[@"delay"];
        if (delayNum) gDelay = [delayNum doubleValue];

        NSNumber *xNum = config[@"x"];
        NSNumber *yNum = config[@"y"];
        if (xNum && yNum) {
            gTapPoint = CGPointMake([xNum doubleValue], [yNum doubleValue]);
        }
        NSLog(@"[AutoClick] Config loaded: delay=%.1f, point=(%.0f, %.0f)", gDelay, gTapPoint.x, gTapPoint.y);
    } else {
        NSLog(@"[AutoClick] No config file, using defaults: delay=%.1f, point=(%.0f, %.0f)", gDelay, gTapPoint.x, gTapPoint.y);
    }
}

// ===== 入口函数（dylib 加载时执行） =====
__attribute__((constructor)) static void entry(void) {
    initGSEvent();
    loadConfig();

    // 延时后在主线程执行点击
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(gDelay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        // 获取 keyWindow 并转换坐标（若需要）
        UIWindow *window = [UIApplication sharedApplication].keyWindow;
        if (!window) {
            NSLog(@"[AutoClick] No key window found, trying any window");
            window = [[[UIApplication sharedApplication] windows] firstObject];
        }
        if (window) {
            CGPoint pointInWindow = CGPointMake(gTapPoint.x, gTapPoint.y);
            NSLog(@"[AutoClick] Tapping at (%.0f, %.0f)", pointInWindow.x, pointInWindow.y);
            simulateTapAtPoint(pointInWindow);
        } else {
            NSLog(@"[AutoClick] No window available");
        }
    });
}