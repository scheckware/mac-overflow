.PHONY: build run run-app clean release app dmg install uninstall test

# Code-signing identity used by `make app`. A STABLE identity (Apple
# Development / Developer ID) makes the Accessibility permission persist across
# rebuilds; ad-hoc signing gives a new identity every build, so macOS re-prompts
# every launch. Auto-detects an "Apple Development" identity; override with:
#   make app CODESIGN_IDENTITY="Developer ID Application: You (TEAMID)"
CODESIGN_IDENTITY ?= $(shell security find-identity -v -p codesigning 2>/dev/null | grep -m1 "Apple Development" | sed -E 's/^[^"]*"([^"]+)".*/\1/')

build:
	swift build

run: build
	.build/debug/MacOverflow

# Build a proper .app bundle and launch it. Use this (not `run`) to test the
# menu bar UI — a bare SPM binary has no bundle identifier, so the status item
# won't respond to clicks and the log fills with intents-registration errors.
run-app: app
	@echo "Launching Mac Overflow..."
	@open build/MacOverflow.app

clean:
	swift package clean
	rm -rf .build build

release:
	swift build -c release --arch arm64 --arch x86_64

app: release
	@echo "Creating app bundle..."
	@mkdir -p build/MacOverflow.app/Contents/MacOS
	@mkdir -p build/MacOverflow.app/Contents/Resources
	@cp "$$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/MacOverflow" build/MacOverflow.app/Contents/MacOS/
	@bash scripts/generate-info-plist.sh > build/MacOverflow.app/Contents/Info.plist
	@if [ -n "$(CODESIGN_IDENTITY)" ]; then \
		echo "Signing with: $(CODESIGN_IDENTITY)"; \
		codesign --force --sign "$(CODESIGN_IDENTITY)" build/MacOverflow.app; \
	else \
		echo "WARNING: no Developer identity found; ad-hoc signing."; \
		echo "         Accessibility permission will NOT persist across rebuilds."; \
		codesign --force --sign - build/MacOverflow.app; \
	fi
	@echo "App bundle created at build/MacOverflow.app"

dmg: app
	@echo "Creating DMG..."
	@command -v create-dmg >/dev/null 2>&1 || brew install create-dmg
	@create-dmg \
		--volname "Mac Overflow" \
		--window-pos 200 120 \
		--window-size 600 400 \
		--icon-size 100 \
		--icon "MacOverflow.app" 175 120 \
		--hide-extension "MacOverflow.app" \
		--app-drop-link 425 120 \
		"build/MacOverflow.dmg" \
		"build/MacOverflow.app" 2>/dev/null || \
	hdiutil create -volname "Mac Overflow" -srcfolder build/MacOverflow.app -ov -format UDZO "build/MacOverflow.dmg"
	@echo "DMG created at build/MacOverflow.dmg"

install: app
	@echo "Installing Mac Overflow..."
	@rm -rf /Applications/MacOverflow.app
	@cp -r build/MacOverflow.app /Applications/
	@echo "Installed to /Applications/MacOverflow.app"

uninstall:
	@echo "Uninstalling Mac Overflow..."
	@rm -rf /Applications/MacOverflow.app
	@echo "Uninstalled"

test:
	swift test
