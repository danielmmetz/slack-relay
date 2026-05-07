DERIVED := build/derived
APP := $(DERIVED)/Build/Products/Release/Relay.app
INSTALLED := /Applications/Relay.app

XCODEBUILD_FLAGS := \
	-project Relay.xcodeproj \
	-scheme Relay \
	-configuration Release \
	-destination 'platform=macOS' \
	-derivedDataPath $(DERIVED) \
	CODE_SIGN_IDENTITY=- \
	CODE_SIGNING_REQUIRED=NO

.PHONY: project build install run clean

project:
	xcodegen generate

build: project
	xcodebuild $(XCODEBUILD_FLAGS) build

install: build
	-pkill -x Relay
	rm -rf $(INSTALLED)
	cp -R $(APP) $(INSTALLED)
	@echo "Installed: $(INSTALLED)"

run: install
	open $(INSTALLED)

clean:
	rm -rf Relay.xcodeproj build
