APP_NAME := KimiStatusBar
BINARY := kimi-statusbar
# Universal binary (Apple Silicon + Intel) so the app works on any Mac.
BUILD_DIR := .build/apple/Products/Release
APP_DIR := dist/$(APP_NAME).app
CONTENTS := $(APP_DIR)/Contents
MACOS := $(CONTENTS)/MacOS
RESOURCES := $(CONTENTS)/Resources
DMG_STAGING := dist/dmg-staging
DMG_PATH := dist/$(APP_NAME).dmg
ZIP_PATH := dist/$(APP_NAME)-macOS.zip

.PHONY: build run app install uninstall zip dmg clean

build:
	swift build -c release --arch arm64 --arch x86_64

run:
	swift run

app: build
	rm -rf "$(APP_DIR)"
	mkdir -p "$(MACOS)" "$(RESOURCES)"
	cp "$(BUILD_DIR)/$(BINARY)" "$(MACOS)/$(APP_NAME)"
	chmod +x "$(MACOS)/$(APP_NAME)"
	cp Resources/completion.mp3 "$(RESOURCES)/completion.mp3"
	cp Resources/update.js Resources/lifecycle.js Resources/install.js Resources/uninstall.js "$(RESOURCES)/"
	printf '%s\n' \
	'<?xml version="1.0" encoding="UTF-8"?>' \
	'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
	'<plist version="1.0">' \
	'<dict>' \
	'  <key>CFBundleExecutable</key>' \
	'  <string>$(APP_NAME)</string>' \
	'  <key>CFBundleIdentifier</key>' \
	'  <string>com.local.kimistatusbar</string>' \
	'  <key>CFBundleName</key>' \
	'  <string>$(APP_NAME)</string>' \
	'  <key>CFBundleDisplayName</key>' \
	'  <string>Kimi Status Bar</string>' \
	'  <key>CFBundlePackageType</key>' \
	'  <string>APPL</string>' \
	'  <key>CFBundleShortVersionString</key>' \
	'  <string>0.1.0</string>' \
	'  <key>CFBundleVersion</key>' \
	'  <string>1</string>' \
	'  <key>LSMinimumSystemVersion</key>' \
	'  <string>13.0</string>' \
	'  <key>LSUIElement</key>' \
	'  <true/>' \
	'</dict>' \
	'</plist>' > "$(CONTENTS)/Info.plist"

# Full local setup: app into /Applications + hooks into ~/.kimi-code/config.toml.
install: app
	rm -rf "/Applications/$(APP_NAME).app"
	cp -R "$(APP_DIR)" /Applications/
	node "/Applications/$(APP_NAME).app/Contents/Resources/install.js"

uninstall:
	-node "/Applications/$(APP_NAME).app/Contents/Resources/uninstall.js"
	-rm -rf "/Applications/$(APP_NAME).app"

# Release archive for GitHub Downloads.
zip: app
	rm -f "$(ZIP_PATH)"
	ditto -c -k --sequesterRsrc --keepParent "$(APP_DIR)" "$(ZIP_PATH)"
	@echo "Created $(ZIP_PATH)"

# Drag-to-install DMG, same as any other macOS app.
dmg: app
	rm -rf "$(DMG_STAGING)" "$(DMG_PATH)"
	mkdir -p "$(DMG_STAGING)"
	cp -R "$(APP_DIR)" "$(DMG_STAGING)/"
	ln -s /Applications "$(DMG_STAGING)/Applications"
	hdiutil create -volname "$(APP_NAME)" -srcfolder "$(DMG_STAGING)" -ov -format UDZO "$(DMG_PATH)"
	rm -rf "$(DMG_STAGING)"
	@echo "Created $(DMG_PATH)"

clean:
	rm -rf .build dist
