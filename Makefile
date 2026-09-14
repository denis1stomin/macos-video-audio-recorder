PROJECT := RexGrab.xcodeproj
SCHEME := RexGrab
CONFIGURATION := Debug
DERIVED_DATA := build
APP_PATH := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)/RexGrab.app

.PHONY: build run test test-desktop clean

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) \
		-destination 'platform=macOS' -derivedDataPath $(DERIVED_DATA) build

run: build
	open $(APP_PATH)

test:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) \
		-destination 'platform=macOS' -derivedDataPath $(DERIVED_DATA) test

# Desktop-dependent integration tests: actually exercise ScreenCaptureKit/AVFoundation against a
# real display/mic. Needs Screen Recording + Microphone permission granted locally to this app's
# signing identity — not runnable in CI, so it's a separate scheme/target from `test` above.
test-desktop:
	xcodebuild -project $(PROJECT) -scheme RexGrabDesktopTests -configuration $(CONFIGURATION) \
		-destination 'platform=macOS' -derivedDataPath $(DERIVED_DATA) test

clean:
	rm -rf $(DERIVED_DATA)
