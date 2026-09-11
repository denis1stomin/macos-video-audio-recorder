PROJECT := RecRex.xcodeproj
SCHEME := RecRex
CONFIGURATION := Debug
DERIVED_DATA := build
APP_PATH := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)/RecRex.app

.PHONY: build run test clean

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) \
		-destination 'platform=macOS' -derivedDataPath $(DERIVED_DATA) CODE_SIGNING_ALLOWED=NO build

run: build
	open $(APP_PATH)

test:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) \
		-destination 'platform=macOS' -derivedDataPath $(DERIVED_DATA) CODE_SIGNING_ALLOWED=NO test

clean:
	rm -rf $(DERIVED_DATA)
