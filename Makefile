# Square Off iOS: common commands.
#   make phone             build, install and launch on the connected iPhone
#   make phone DEVICE=<udid> TEAM=<team id>   another device or team
#   make devices           list connected devices (find the UDID)
#   make generate | build | test

DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
export DEVELOPER_DIR

PROJECT   := SquareOff.xcodeproj
SCHEME    := SquareOff
BUNDLE_ID := com.novastrada.squareoff
# iPhone 14 "HODOR14" and the Apple Development team in Xcode.
DEVICE    ?= 00008110-001A026A3E39401E
TEAM      ?= 5M999SV4VM
SIMULATOR ?= iPhone 17

DEVICE_APP := build-device/Build/Products/Debug-iphoneos/SquareOff.app

.PHONY: phone phone-build phone-install phone-launch devices generate build test

phone: phone-build phone-install phone-launch

phone-build: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-destination 'id=$(DEVICE)' -derivedDataPath build-device \
		-allowProvisioningUpdates DEVELOPMENT_TEAM=$(TEAM) build -quiet

phone-install:
	xcrun devicectl device install app --device $(DEVICE) $(DEVICE_APP)

# Launching needs the phone unlocked; the app is installed either way.
phone-launch:
	@xcrun devicectl device process launch --device $(DEVICE) $(BUNDLE_ID) >/dev/null 2>&1 \
		&& echo "Launched Square Off on $(DEVICE)." \
		|| echo "Installed. Unlock the phone and open Square Off (it can't launch while the phone is locked)."

devices:
	xcrun devicectl list devices

generate:
	xcodegen generate --quiet

build: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination 'platform=iOS Simulator,name=$(SIMULATOR)' -derivedDataPath build build -quiet

test: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination 'platform=iOS Simulator,name=$(SIMULATOR)' -derivedDataPath build test -quiet
