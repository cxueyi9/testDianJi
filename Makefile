export THEOS = /opt/theos
export ARCHS = arm64 arm64e
export TARGET = iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AutoClick

AutoClick_FILES = Tweak.xm \
    PTFakeMetaTouch.m \
    UITouch-KIFAdditions.m \
    UIEvent+KIFAdditions.m \
    IOHIDEvent+KIF.m

AutoClick_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unguarded-availability -Wno-unused-function -I. -DDLog=NSLog -DRLog=NSLog
AutoClick_LDFLAGS = -framework UIKit -framework Foundation -framework QuartzCore -framework IOKit
AutoClick_CODESIGN = NO

include $(THEOS_MAKE_PATH)/tweak.mk