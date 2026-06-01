# Build unsigned and signed IPA for encx-cli (macOS + Xcode required).
#
# Examples:
#   make unsigned-ipa
#   make signed-ipa
#   make framework
#   make signed-ipa EXPORT_METHOD=release-testing
#   make ipa DEVELOPMENT_TEAM=XXXXXXXXXX

.SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DELETE_ON_ERROR:

ifeq ($(shell uname -s),Darwin)
  XCODEBUILD := xcodebuild
else
  $(error iOS IPA builds require macOS with Xcode installed)
endif

# Checkout of github.com/skrashevich/encx-cli (gomobile bind). Override if elsewhere:
#   make framework ENCX_CLI_ROOT=/path/to/encx-cli
# CI / vendored xcframework: make unsigned-ipa SKIP_FRAMEWORK=1
SKIP_FRAMEWORK ?= 0
ENCX_CLI_ROOT ?= $(abspath ../encx-cli)
IOS_DIR := $(abspath .)
PROJECT := encx-cli.xcodeproj
SCHEME := encx-cli
APP := encx-cli
CONFIGURATION ?= Release
XCODE_DEST := generic/platform=iOS

BUILD_DIR := build
GOMOBILE_OUT := $(ENCX_CLI_ROOT)/build/gomobile
FRAMEWORK_DIR := encx-cli/Frameworks
ENCX_FRAMEWORK := $(FRAMEWORK_DIR)/Encx.xcframework
DERIVED_DATA := $(BUILD_DIR)/DerivedData
APP_PRODUCT := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)-iphoneos/$(APP).app
ARCHIVE := $(BUILD_DIR)/$(APP).xcarchive
EXPORT_DIR := $(BUILD_DIR)/export
EXPORT_OPTIONS := $(BUILD_DIR)/ExportOptions.plist
EXPORT_OPTIONS_TEMPLATE := export/ExportOptions.plist

DEVELOPMENT_TEAM ?= ZLQX2C6SX2
# Xcode 16+: debugging | release-testing | app-store-connect | enterprise
# Legacy aliases: development -> debugging, ad-hoc -> release-testing, app-store -> app-store-connect
EXPORT_METHOD ?= debugging

VERSION := $(strip $(shell $(XCODEBUILD) -project "$(PROJECT)" -scheme "$(SCHEME)" -configuration "$(CONFIGURATION)" -destination "$(XCODE_DEST)" -showBuildSettings 2>/dev/null | awk -F' = ' '/ MARKETING_VERSION / {print $$2; exit}'))
BUILD_NUMBER := $(strip $(shell $(XCODEBUILD) -project "$(PROJECT)" -scheme "$(SCHEME)" -configuration "$(CONFIGURATION)" -destination "$(XCODE_DEST)" -showBuildSettings 2>/dev/null | awk -F' = ' '/ CURRENT_PROJECT_VERSION / {print $$2; exit}'))
# GNU make treats "0.x" as false in $(if); use string prefix instead.
VERSION_SUFFIX := $(if $(VERSION),-v$(VERSION),)$(if $(BUILD_NUMBER),-b$(BUILD_NUMBER),)

UNSIGNED_IPA := $(BUILD_DIR)/$(APP)$(VERSION_SUFFIX)-unsigned.ipa
SIGNED_IPA := $(BUILD_DIR)/$(APP)$(VERSION_SUFFIX).ipa

# Normalize legacy export method names
EXPORT_METHOD := $(subst development,debugging,$(EXPORT_METHOD))
EXPORT_METHOD := $(subst ad-hoc,release-testing,$(EXPORT_METHOD))
EXPORT_METHOD := $(subst app-store,app-store-connect,$(EXPORT_METHOD))

.PHONY: all help clean ipa unsigned-ipa signed-ipa unsigned signed archive export framework

all: ipa

help:
	@echo "enkapp iOS IPA build"
	@echo ""
	@echo "Targets:"
	@echo "  framework      rebuild $(ENCX_FRAMEWORK) via gomobile (mobile/bind-ios.sh)"
	@echo "  unsigned-ipa   $(UNSIGNED_IPA)  (framework, then unsigned build)"
	@echo "  signed-ipa     $(SIGNED_IPA)    (framework, then signed archive/export)"
	@echo "  ipa            both unsigned and signed"
	@echo "  clean          remove $(BUILD_DIR)/"
	@echo ""
	@echo "Variables:"
	@echo "  CONFIGURATION=$(CONFIGURATION)"
	@echo "  DEVELOPMENT_TEAM=$(DEVELOPMENT_TEAM)"
	@echo "  EXPORT_METHOD=$(EXPORT_METHOD)  (signed export only)"
	@echo "  BUILD_DIR=$(BUILD_DIR)"
	@echo "  SKIP_FRAMEWORK=$(SKIP_FRAMEWORK)  (1 = use vendored Encx.xcframework)"
	@echo ""
	@echo "Signed export methods (Xcode 16+):"
	@echo "  debugging          install on devices in your team (default)"
	@echo "  release-testing    Ad Hoc / limited distribution"
	@echo "  app-store-connect  App Store / TestFlight"
	@echo "  enterprise         Apple Enterprise program"

ipa: unsigned-ipa signed-ipa

framework:
	@test -f "$(ENCX_CLI_ROOT)/mobile/bind-ios.sh" || { \
		echo "encx-cli not found at $(ENCX_CLI_ROOT); set ENCX_CLI_ROOT"; exit 1; \
	}
	mkdir -p "$(GOMOBILE_OUT)"
	"$(ENCX_CLI_ROOT)/mobile/bind-ios.sh" "$(GOMOBILE_OUT)"
	rsync -a --delete "$(GOMOBILE_OUT)/Encx.xcframework/" "$(ENCX_FRAMEWORK)/"
	@echo "==> $(ENCX_FRAMEWORK) (from $(GOMOBILE_OUT))"

unsigned: unsigned-ipa
signed: signed-ipa

unsigned-ipa: $(UNSIGNED_IPA)

signed-ipa: $(SIGNED_IPA)

clean:
	rm -rf "$(BUILD_DIR)"

$(BUILD_DIR):
	mkdir -p "$(BUILD_DIR)"

$(EXPORT_OPTIONS): $(EXPORT_OPTIONS_TEMPLATE) | $(BUILD_DIR)
	cp "$(EXPORT_OPTIONS_TEMPLATE)" "$(EXPORT_OPTIONS)"
	plutil -replace method -string "$(EXPORT_METHOD)" "$(EXPORT_OPTIONS)"
	if plutil -extract teamID xml1 "$(EXPORT_OPTIONS)" >/dev/null 2>&1; then \
		plutil -replace teamID -string "$(DEVELOPMENT_TEAM)" "$(EXPORT_OPTIONS)"; \
	else \
		plutil -insert teamID -string "$(DEVELOPMENT_TEAM)" "$(EXPORT_OPTIONS)"; \
	fi

ifeq ($(SKIP_FRAMEWORK),1)
$(APP_PRODUCT): | $(BUILD_DIR)
else
$(APP_PRODUCT): framework | $(BUILD_DIR)
endif
	@test -d "$(ENCX_FRAMEWORK)" || { echo "missing $(ENCX_FRAMEWORK); run make framework or set SKIP_FRAMEWORK=0"; exit 1; }
	$(XCODEBUILD) build \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration "$(CONFIGURATION)" \
		-destination "$(XCODE_DEST)" \
		-derivedDataPath "$(DERIVED_DATA)" \
		CODE_SIGNING_ALLOWED=NO \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGN_IDENTITY=- \
		DEVELOPMENT_TEAM=

$(UNSIGNED_IPA): $(APP_PRODUCT)
	@rm -rf "$(BUILD_DIR)/unsigned-payload"
	@mkdir -p "$(BUILD_DIR)/unsigned-payload/Payload"
	cp -R "$(APP_PRODUCT)" "$(BUILD_DIR)/unsigned-payload/Payload/"
	cd "$(BUILD_DIR)/unsigned-payload" && zip -qr "../$(notdir $(UNSIGNED_IPA))" Payload
	@echo "==> $(UNSIGNED_IPA)"

$(ARCHIVE): framework
	$(XCODEBUILD) archive \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration "$(CONFIGURATION)" \
		-destination "$(XCODE_DEST)" \
		-archivePath "$(ARCHIVE)" \
		DEVELOPMENT_TEAM="$(DEVELOPMENT_TEAM)"

$(SIGNED_IPA): $(ARCHIVE) $(EXPORT_OPTIONS)
	@rm -rf "$(EXPORT_DIR)"
	$(XCODEBUILD) -exportArchive \
		-archivePath "$(ARCHIVE)" \
		-exportPath "$(EXPORT_DIR)" \
		-exportOptionsPlist "$(EXPORT_OPTIONS)"
	@mv "$(EXPORT_DIR)/$(APP).ipa" "$@"
	@echo "==> $@"
