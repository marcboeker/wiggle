APP_NAME  := Wiggle
BUNDLE_ID := com.marcboeker.wiggle
CONFIG    := release
VERSION   ?= main

# ARCH selects a cross-compilation target (e.g. "arm64" or "x86_64") and builds
# into an arch-specific scratch/output dir so both can be built without
# clobbering each other. Leave unset for a plain native build, the one
# `run`/`install` use.
ARCH ?=
ifeq ($(ARCH),)
SWIFT_BUILD_DIR   := .build/$(CONFIG)
SWIFT_BUILD_FLAGS :=
APP               := build/$(APP_NAME).app
else
SWIFT_BUILD_DIR   := .build-$(ARCH)/$(CONFIG)
SWIFT_BUILD_FLAGS := --arch $(ARCH) --scratch-path .build-$(ARCH)
APP               := build/$(ARCH)/$(APP_NAME).app
endif

BIN := $(SWIFT_BUILD_DIR)/wiggle

# A real signing identity keeps the Accessibility permission across rebuilds,
# because macOS then identifies the app by team and bundle id instead of by the
# hash of the binary. Falls back to an ad hoc signature, which is what CI and
# a downloaded release use.
SIGN_ID := $(or $(SIGN_ID),$(shell security find-identity -v -p codesigning 2>/dev/null \
	| awk '/Apple Development/ { print $$2; exit }'),-)

.PHONY: all build bundle run stop test clean logs permissions

all: bundle

build:
	swift build -c $(CONFIG) $(SWIFT_BUILD_FLAGS)

# The *.bundle copies hold the KeyboardShortcuts localizations that
# Bundle.module looks up in Contents/Resources.
bundle: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp $(BIN) $(APP)/Contents/MacOS/$(APP_NAME)
	cp -R $(SWIFT_BUILD_DIR)/*.bundle $(APP)/Contents/Resources/
	cp Resources/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	plutil -replace CFBundleShortVersionString -string "$(VERSION)" $(APP)/Contents/Info.plist
	codesign --force --sign $(SIGN_ID) --identifier $(BUNDLE_ID) $(APP)
	@echo "built $(APP) (signed with $(SIGN_ID))"

run: stop bundle
	open $(APP)

stop:
	@pkill -x $(APP_NAME) 2>/dev/null || true

test:
	swift test

logs:
	log stream --style compact --predicate 'process == "$(APP_NAME)"'

permissions:
	open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

clean:
	rm -rf build .build .build-*
