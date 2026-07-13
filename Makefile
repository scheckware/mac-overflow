.PHONY: build run run-app clean release app dmg notarize dist install uninstall test

# Code-signing identity used by `make app`. Prefers a "Developer ID Application"
# identity (required for notarization / sharing with others), then falls back to
# "Apple Development" (fine for local use), then ad-hoc. A STABLE identity makes
# the Accessibility permission persist across rebuilds; ad-hoc signing gives a
# new identity every build, so macOS re-prompts every launch. Override with:
#   make app CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
CODESIGN_IDENTITY ?= $(shell security find-identity -v -p codesigning 2>/dev/null | grep -m1 "Developer ID Application" | sed -E 's/^[^"]*"([^"]+)".*/\1/'; )
ifeq ($(strip $(CODESIGN_IDENTITY)),)
CODESIGN_IDENTITY := $(shell security find-identity -v -p codesigning 2>/dev/null | grep -m1 "Apple Development" | sed -E 's/^[^"]*"([^"]+)".*/\1/')
endif

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
	@cp LICENSE build/MacOverflow.app/Contents/Resources/LICENSE.txt
	@if [ -n "$(CODESIGN_IDENTITY)" ]; then \
		echo "Signing with: $(CODESIGN_IDENTITY)"; \
		codesign --force --options runtime --timestamp --sign "$(CODESIGN_IDENTITY)" build/MacOverflow.app; \
	else \
		echo "WARNING: no Developer identity found; ad-hoc signing."; \
		echo "         Accessibility permission will NOT persist across rebuilds."; \
		codesign --force --sign - build/MacOverflow.app; \
	fi
	@echo "App bundle created at build/MacOverflow.app"

dmg: app
	@bash scripts/make-dmg.sh build/MacOverflow.app build/MacOverflow.dmg

# Notarize + staple the already-built .app (run `make app` first). Requires a
# Developer ID signature (make app provides it) and notary credentials — either a
# keychain profile (NOTARY_PROFILE, default "MacOverflow") or App Store Connect
# API key env vars (NOTARY_KEY_ID / NOTARY_ISSUER_ID / NOTARY_KEY_PATH).
notarize:
	@bash scripts/notarize.sh build/MacOverflow.app

# Full distributable pipeline: build + sign, notarize + staple, then package a
# stapled DMG + ZIP that open with no Gatekeeper warning on any Mac.
dist: app notarize
	@bash scripts/make-dmg.sh build/MacOverflow.app build/MacOverflow.dmg
	@rm -f build/MacOverflow.zip
	@/usr/bin/ditto -c -k --keepParent build/MacOverflow.app build/MacOverflow.zip
	@echo "Distributables ready: build/MacOverflow.dmg, build/MacOverflow.zip (notarized + stapled)"

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
