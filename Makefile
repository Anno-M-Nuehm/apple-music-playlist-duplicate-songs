# Playlist Deduplicator — Makefile
#
# Targets (see `make help`):
#   xcodeproj    generate the Xcode project from project.yml (xcodegen)
#   clean        clean the build (xcodebuild clean)
#   build        build the project for running
#   build-test   build the project for testing
#   test         run the test suite
#   run          build and run the app
#   all          clean -> build -> build-test -> test
#   help         list all targets
#
# The Xcode project file is not checked in; `xcodeproj` is a prerequisite
# of the build targets and regenerates it (requires xcodegen:
# brew install xcodegen).

PROJECT     := PlaylistDeduplicator
SCHEME      := PlaylistDeduplicator
CONFIG      := Debug
DESTINATION := platform=macOS

# Use Apple's toolchain only. A conda/miniforge cross toolchain earlier
# in the interactive shell's PATH hijacks xcodebuild's compiler and
# linker invocations (arm64-apple-darwin20.0.0-ld rejects -Xlinker,
# its clang rejects -index-store-path); Xcode UI builds are unaffected
# because they do not inherit the shell PATH. Keep the standard
# third-party tool locations (homebrew) so xcodegen & friends still
# resolve, but ahead of them Apple's toolchain, and drop everything
# else (notably conda/miniforge) from the inherited PATH.
XCODE_DEVELOPER_DIR := $(shell xcode-select -p)
export PATH := $(XCODE_DEVELOPER_DIR)/Toolchains/XcodeDefault.xctoolchain/usr/bin:$(XCODE_DEVELOPER_DIR)/usr/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin

.PHONY: all help xcodeproj clean build build-test test run

help: ## List available targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "} {printf "  %-12s %s\n", $$1, $$2}'

all: clean build build-test test ## clean, then build, build-test, and test

xcodeproj: ## Generate the Xcode project from project.yml
	xcodegen generate

clean: ## Clean the build
	xcodebuild -project $(PROJECT).xcodeproj -scheme $(SCHEME) -configuration $(CONFIG) clean

build: xcodeproj ## Build for running
	xcodebuild -project $(PROJECT).xcodeproj -scheme $(SCHEME) -configuration $(CONFIG) build

build-test: xcodeproj ## Build for testing
	xcodebuild -project $(PROJECT).xcodeproj -scheme $(SCHEME) -configuration $(CONFIG) build-for-testing

test: xcodeproj ## Run the test suite
	xcodebuild -project $(PROJECT).xcodeproj -scheme $(SCHEME) -configuration $(CONFIG) -destination '$(DESTINATION)' test

run: build ## Build and run the app
	@APP="$$(xcodebuild -project $(PROJECT).xcodeproj -scheme $(SCHEME) -configuration $(CONFIG) -showBuildSettings 2>/dev/null | awk -F' = ' '/^ *BUILT_PRODUCTS_DIR/{print $$2; exit}')/$(PROJECT).app"; \
	if [ -d "$$APP" ]; then open "$$APP"; else \
		echo "App not found at: $$APP"; exit 1; \
	fi
