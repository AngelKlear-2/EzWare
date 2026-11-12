TARGET := iphone:clang:latest:15.0
ARCHS = arm64

# palera1n / rootless jailbreak (iOS 15 on A10). Build with: make package ROOTLESS=1
ifeq ($(ROOTLESS),1)
export THEOS_PACKAGE_SCHEME = rootless
endif

INSTALL_TARGET_PROCESSES = StandChillow

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = EzWare

EzWare_FILES = Tweak.m
EzWare_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-function
EzWare_FRAMEWORKS = UIKit QuartzCore Foundation
EzWare_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk
