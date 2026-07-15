# Theos build — produces a .deb installable via Sileo/Zebra on a jailbroken device.
#
# This is the distribution-oriented alternative to the Xcode/XcodeGen path (project.yml).
# NOTE: SWCompression (used for .xz decompression) is a SwiftPM package and is easiest to
# consume via Xcode. Under Theos you must vendor it or add it to SUBPROJECTS; see README.
#
# Usage:
#   export THEOS_DEVICE_IP=<device-ip>
#   make package install

TARGET := iphone:clang:latest:14.0
ARCHS := arm64
INSTALL_TARGET_PROCESSES := FridaLauncher

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = FridaLauncher

FridaLauncher_FILES = $(shell find FridaLauncher -name '*.swift')
FridaLauncher_FRAMEWORKS = UIKit
FridaLauncher_SWIFTFLAGS = -ISWCompression
FridaLauncher_CODESIGN_FLAGS = -Sentitlements.plist
FridaLauncher_INSTALL_PATH = /Applications

include $(THEOS_MAKE_PATH)/application.mk
