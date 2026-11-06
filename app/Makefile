# OpenControl for PreSonus FireStudio — "OpenControl" app
#   make                       → native build
#   make ARCHS="x86_64 arm64"  → Universal Binary
#   make install               → copy to /Applications
#   make pkg                   → app-only installer package
#   make zip                   → .zip archive of the app

VERSION ?= $(shell cat ../VERSION)
BUILD   ?= 1
ARCHS   ?= $(shell uname -m)
MINOS   = 12.0

APP  = build/OpenControl.app
BIN  = $(APP)/Contents/MacOS/OpenControl
ICNS = build/AppIcon.icns
SWIFT = Sources/L10n.swift Sources/RegisterMap.swift Sources/MixerModel.swift Sources/Controls.swift Sources/Presets.swift Sources/DriverSettings.swift Sources/Views.swift

all: $(BIN)

build/fsfw-%.o: Sources/fsfw.c Sources/fsfw.h
	mkdir -p build
	clang -O2 -Wall -Wno-deprecated-declarations -arch $* -mmacosx-version-min=$(MINOS) -c Sources/fsfw.c -o $@

build/OpenControl-%: build/fsfw-%.o $(SWIFT)
	swiftc -O -parse-as-library -target $*-apple-macosx$(MINOS) -import-objc-header Sources/fsfw.h \
	  $(SWIFT) $< -framework IOKit -framework CoreAudio -framework CoreFoundation -o $@

$(ICNS): tools/make_icon.swift
	mkdir -p build/AppIcon.iconset
	swift tools/make_icon.swift build/icon_1024.png
	for s in 16 32 128 256 512; do \
	  sips -z $$s $$s build/icon_1024.png --out build/AppIcon.iconset/icon_$${s}x$${s}.png >/dev/null; \
	  d=$$((s*2)); sips -z $$d $$d build/icon_1024.png --out build/AppIcon.iconset/icon_$${s}x$${s}@2x.png >/dev/null; \
	done
	iconutil -c icns build/AppIcon.iconset -o $@

$(BIN): $(foreach a,$(ARCHS),build/OpenControl-$(a)) Info.plist $(ICNS) $(wildcard Resources/*.lproj/*.strings)
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	sed -e 's/__VERSION__/$(VERSION)/' -e 's/__BUILD__/$(BUILD)/' Info.plist > "$(APP)/Contents/Info.plist"
	cp $(ICNS) "$(APP)/Contents/Resources/AppIcon.icns"
	cp -R Resources/*.lproj "$(APP)/Contents/Resources/"
	lipo -create $(foreach a,$(ARCHS),build/OpenControl-$(a)) -output "$(BIN)"
	codesign --force -s - "$(APP)"
	@echo "Architectures : $$(lipo -archs "$(BIN)")"

pkg: all
	pkgbuild --component "$(APP)" --install-location /Applications --scripts pkg-scripts \
	  --identifier io.github.opencontrol-firestudio.mixer --version $(VERSION) \
	  "build/OpenControl-FireStudio-$(VERSION)-app.pkg"

zip: all
	cd build && ditto -c -k --keepParent "OpenControl.app" "OpenControl-FireStudio-$(VERSION)-app.zip"

install: all
	-pkill -TERM -f "OpenControl.app/Contents/MacOS/OpenControl"; sleep 1
	# Versions up to 1.2 were installed as "FireStudio Mixer.app".
	-pkill -TERM -f "FireStudio Mixer.app/Contents/MacOS/FireStudioMixer"; sleep 1
	rm -rf "/Applications/FireStudio Mixer.app"
	ditto "$(APP)" "/Applications/OpenControl.app"
	@echo "Installed: /Applications/OpenControl.app"

clean:
	rm -rf build

.PHONY: all pkg zip install clean
.SECONDARY:
