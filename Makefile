export THEOS = /opt/theos
export ARCHS = arm64 arm64e
export TARGET = iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AutoClick
AutoClick_FILES = Tweak.xm
AutoClick_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
AutoClick_CODESIGN = NO

include $(THEOS_MAKE_PATH)/tweak.mk