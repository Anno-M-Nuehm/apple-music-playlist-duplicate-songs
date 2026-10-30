# Playlist Deduplicator — Makefile
#
# Targets:
#   xcodeproj    generate the Xcode project from project.yml (xcodegen)
#   clean        clean the build (xcodebuild clean)
#   build        build for running (xcodebuild build)
#   build-test   build for testing (xcodebuild build-for-testing)
#   test         run the test suite (xcodebuild test)
#   run          build and run the app
#
# The Xcode project file is not checked in; run `make xcodeproj` once
# after cloning (requires xcodegen: brew install xcodegen).

PROJECT   := PlaylistDeduplicator
SCHEME    := PlaylistDeduplicator
CONFIG    := Debug
DESTINATION := platform=macOS

.PHONY: xcodeproj clean build build-test test run

xcodeproj:
	xcodegen generate

clean:
	xcodebuild -project $(PROJECT).xcodeproj -scheme $(SCHEME) -configuration $(CONFIG) clean

build: xcodeproj
	xcodebuild -project $(PROJECT).xcodeproj -scheme $(SCHEME) -configuration $(CONFIG) build

build-test: xcodeproj
	xcodebuild -project $(PROJECT).xcodeproj -scheme $(SCHEME) -configuration $(CONFIG) build-for-testing

test: xcodeproj
	xcodebuild -project $(PROJECT).xcodeproj -scheme $(SCHEME) -configuration $(CONFIG) -destination '$(DESTINATION)' test

run: build
	@APP="$$(xcodebuild -project $(PROJECT).xcodeproj -scheme $(SCHEME) -configuration $(CONFIG) -showBuildSettings 2>/dev/null | awk -F' = ' '/^ *BUILT_PRODUCTS_DIR/{print $$2; exit}')/$(PROJECT).app"; \
	if [ -d "$$APP" ]; then open "$$APP"; else \
		echo "App not found at: $$APP"; exit 1; \
	fi
