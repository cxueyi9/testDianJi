export THEOS = /opt/theos
export ARCHS = arm64 arm64e
export TARGET = iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AutoClick

AutoClick_FILES = Tweak.xm \
    CALayer-KIFAdditions.m \
    CGGeometry-KIFAdditions.m \
    IOHIDEvent+KIF.m \
    NSBundle-KIFAdditions.m \
    NSError-KIFAdditions.m \
    NSException-KIFAdditions.m \
    NSFileManager-KIFAdditions.m \
    NSPredicate+KIFAdditions.m \
    NSString+KIFAdditions.m \
    PTFakeMetaTouch.m \
    UIAccessibilityElement-KIFAdditions.m \
    UIApplication-KIFAdditions.m \
    UIEvent+KIFAdditions.m \
    UIScreen+KIFAdditions.m \
    UIScrollView-KIFAdditions.m \
    UITableView-KIFAdditions.m \
    UITouch-KIFAdditions.m \
    UIView-Debugging.m \
    UIView-KIFAdditions.m \
    UIWindow-KIFAdditions.m \
    XCTestCase-KIFAdditions.m


AutoClick_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unguarded-availability -Wno-unused-function -I.
AutoClick_LDFLAGS = -framework UIKit -framework Foundation -framework QuartzCore -framework IOKit
AutoClick_CODESIGN = NO

include $(THEOS_MAKE_PATH)/tweak.mk