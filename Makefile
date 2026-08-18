export THEOS = /opt/theos
export ARCHS = arm64 arm64e
export TARGET = iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AutoClick

# 仅保留必要的 .m 文件
AutoClick_FILES = Tweak.xm \
    PTFakeMetaTouch.m \
    UITouch-KIFAdditions.m \
    UIEvent+KIFAdditions.m \
    UIApplication-KIFAdditions.m \
    IOHIDEvent+KIF.m \
    UIView-KIFAdditions.m \
    CGGeometry-KIFAdditions.m \
    UIAccessibilityElement-KIFAdditions.m \
    UIScrollView-KIFAdditions.m \
    UITableView-KIFAdditions.m \
    UIScreen+KIFAdditions.m \
    CALayer-KIFAdditions.m \
    NSString+KIFAdditions.m \
    NSError-KIFAdditions.m \
    NSException-KIFAdditions.m \
    NSFileManager-KIFAdditions.m \
    NSPredicate+KIFAdditions.m \
    UIView-Debugging.m \
    UIWindow-KIFAdditions.m

AutoClick_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unguarded-availability -Wno-unused-function -I.
AutoClick_LDFLAGS = -framework UIKit -framework Foundation -framework QuartzCore -framework IOKit
AutoClick_CODESIGN = NO

include $(THEOS_MAKE_PATH)/tweak.mk