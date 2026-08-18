export THEOS = /opt/theos
export ARCHS = arm64 arm64e
export TARGET = iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AutoClick

AutoClick_FILES = Tweak.xm \
    CALayer-KIFAdditions.h \
    CALayer-KIFAdditions.m \
    CGGeometry-KIFAdditions.h \
    CGGeometry-KIFAdditions.m \
    FixCategoryBug.h \
    IOHIDEvent+KIF.h \
    IOHIDEvent+KIF.m \
    LoadableCategory.h \
    Makefile \
    NSBundle-KIFAdditions.h \
    NSBundle-KIFAdditions.m \
    NSError-KIFAdditions.h \
    NSError-KIFAdditions.m \
    NSException-KIFAdditions.h \
    NSException-KIFAdditions.m \
    NSFileManager-KIFAdditions.h \
    NSFileManager-KIFAdditions.m \
    NSPredicate+KIFAdditions.h \
    NSPredicate+KIFAdditions.m \
    NSString+KIFAdditions.h \
    NSString+KIFAdditions.m \
    PTFakeMetaTouch.h \
    PTFakeMetaTouch.m \
    PTFakeTouch.h \
    UIAccessibilityElement-KIFAdditions.h \
    UIAccessibilityElement-KIFAdditions.m \
    UIApplication-KIFAdditions.h \
    UIApplication-KIFAdditions.m \
    UIEvent+KIFAdditions.h \
    UIEvent+KIFAdditions.m \
    UIScreen+KIFAdditions.h \
    UIScreen+KIFAdditions.m \
    UIScrollView-KIFAdditions.h \
    UIScrollView-KIFAdditions.m \
    UITableView-KIFAdditions.h \
    UITableView-KIFAdditions.m \
    UITouch-KIFAdditions.h \
    UITouch-KIFAdditions.m \
    UIView-Debugging.h \
    UIView-Debugging.m \
    UIView-KIFAdditions.h \
    UIView-KIFAdditions.m \
    UIWindow-KIFAdditions.h \
    UIWindow-KIFAdditions.m \
    XCTestCase-KIFAdditions.h \
    XCTestCase-KIFAdditions.m


AutoClick_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unguarded-availability -Wno-unused-function -I.
AutoClick_LDFLAGS = -framework UIKit -framework Foundation -framework QuartzCore -framework IOKit
AutoClick_CODESIGN = NO

include $(THEOS_MAKE_PATH)/tweak.mk