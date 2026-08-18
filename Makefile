export THEOS = /opt/theos
TARGET = iphone:clang:latest:10.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AutoClick
AutoClick_FILES = Tweak.xm
AutoClick_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk