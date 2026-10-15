# ──────────────────────────────────────────────
# AssetFlow — Development Makefile
# ──────────────────────────────────────────────

# Project settings
PROJECT    := AssetFlow.xcodeproj
SCHEME     := AssetFlow
CONFIG     := Release
BUILD_DIR  := build
ARCHIVE    := $(BUILD_DIR)/$(SCHEME).xcarchive
APP        := $(BUILD_DIR)/$(SCHEME).app
DESTINATION := platform=macOS

# ── Targets ───────────────────────────────────

.PHONY: all build test lint clean

## Default target
all: build

## Archive a Release build (unsigned, suitable for local use)
build:
	xcodebuild archive \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration $(CONFIG) \
		-archivePath $(ARCHIVE) \
		CODE_SIGN_IDENTITY="" \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=NO
	cp -R $(ARCHIVE)/Products/Applications/$(SCHEME).app $(APP)
	@echo "\n✅ Build complete: $(APP)"

## Run the test suite
test:
	xcodebuild test \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination '$(DESTINATION)'

## Run all pre-commit hooks (swift-format + SwiftLint)
lint:
	uv run pre-commit run --all-files

## Remove build artifacts
clean:
	rm -rf $(BUILD_DIR)/
