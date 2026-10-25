# Square Off iOS: common commands.
#   make phone             build, install and launch on the connected iPhone
#   make phone DEVICE=<udid> TEAM=<team id>   another device or team
#   make devices           list connected devices (find the UDID)
#   make generate | build | test
#   make archive | export | testflight        Release archive, .ipa, upload to App Store Connect
#   make bump [VERSION=x.y.z] [BUILD=n]       version/build in project.yml (build +1 by default)
#   make release-check                        archive and verify plist, entitlements, icon, privacy manifest

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

ARCHIVE     := build-archive/SquareOff.xcarchive
ARCHIVE_APP := $(ARCHIVE)/Products/Applications/SquareOff.app
EXPORT_DIR  := build-archive/export
IPA         := $(EXPORT_DIR)/SquareOff.ipa
ICON        := SquareOff/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png
# App Store Connect API key (Users and Access › Integrations): the .p8 lives in
# ~/.appstoreconnect/private_keys/AuthKey_$(ASC_KEY_ID).p8
ASC_KEY_ID    ?=
ASC_ISSUER_ID ?=

.PHONY: phone phone-build phone-install phone-launch devices generate build test \
	archive export testflight bump release-check

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

# --- Release -----------------------------------------------------------------------------

archive: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-destination 'generic/platform=iOS' -archivePath $(ARCHIVE) \
		-allowProvisioningUpdates DEVELOPMENT_TEAM=$(TEAM) archive -quiet

export: archive
	xcodebuild -exportArchive -archivePath $(ARCHIVE) -exportPath $(EXPORT_DIR) \
		-exportOptionsPlist ExportOptions.plist -allowProvisioningUpdates -quiet

testflight: export
	@test -n "$(ASC_KEY_ID)" -a -n "$(ASC_ISSUER_ID)" || \
		{ echo "Set ASC_KEY_ID and ASC_ISSUER_ID (key file: ~/.appstoreconnect/private_keys/AuthKey_<id>.p8)"; exit 1; }
	xcrun altool --upload-app -t ios -f $(IPA) --apiKey $(ASC_KEY_ID) --apiIssuer $(ASC_ISSUER_ID)

# agvtool is useless with a generated project: project.yml is the only durable place for versions.
bump:
	@cur=$$(sed -nE 's/^ *CURRENT_PROJECT_VERSION: "([0-9]+)"/\1/p' project.yml | head -1); next=$${BUILD:-$$((cur + 1))}; \
	sed -i '' -E "s/^( *CURRENT_PROJECT_VERSION: \")[0-9]+/\1$$next/" project.yml; \
	if [ -n "$(VERSION)" ]; then sed -i '' -E 's/^( *MARKETING_VERSION: ")[^"]+/\1$(VERSION)/' project.yml; fi; \
	xcodegen generate --quiet; grep -E 'MARKETING_VERSION|CURRENT_PROJECT_VERSION' project.yml

release-check: archive
	@echo "--- Info.plist"; plutil -p $(ARCHIVE_APP)/Info.plist | grep -E 'Version|NonExempt|Category|BundleIdentifier'
	@echo "--- entitlements"; codesign -d --entitlements :- $(ARCHIVE_APP) 2>/dev/null | grep -E 'associated-domains|applesignin|square-off' || echo "MISSING entitlements"
	@echo "--- icon alpha (expect: no)"; sips -g hasAlpha $(ICON) | tail -1
	@echo "--- privacy manifest"; test -f $(ARCHIVE_APP)/PrivacyInfo.xcprivacy && echo "PrivacyInfo.xcprivacy present" || echo "MISSING PrivacyInfo.xcprivacy"
