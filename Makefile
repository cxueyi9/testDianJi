export THEOS = /opt/theos
# 修改这一行：只指定 arm64 和 arm64e 架构
export ARCHS = arm64 arm64e
# 指定目标平台和最低系统版本
export TARGET = iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AutoClick
AutoClick_FILES = Tweak.xm
AutoClick_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk