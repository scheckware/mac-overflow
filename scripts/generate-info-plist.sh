#!/bin/bash
# Source of truth for the app version (this is an SPM project — no Xcode project).
#   MARKETING_VERSION -> CFBundleShortVersionString  (bumped for real releases)
#   BUILD_NUMBER      -> CFBundleVersion             (bumped every build; see the
#                                                     bump-build skill)
MARKETING_VERSION="${MARKETING_VERSION:-1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-6}"

cat << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>MacOverflow</string>
    <key>CFBundleIdentifier</key>
    <string>com.omniaura.mac-overflow</string>
    <key>CFBundleName</key>
    <string>Mac Overflow</string>
    <key>CFBundleDisplayName</key>
    <string>Mac Overflow</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${MARKETING_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Scheckware fork · MIT License. Based on Mac Overflow © 2026 Omni Aura.</string>
</dict>
</plist>
EOF
