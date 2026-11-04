# OpenControl for PreSonus FireStudio — application « FireStudio Mixer »
#   make                       → build natif
#   make ARCHS="x86_64 arm64"  → Universal Binary
#   make install               → copie dans /Applications
#   make pkg                   → installeur de l'application seule
#   make zip                   → archive .zip de l'application

VERSION ?= $(shell cat ../VERSION)
BUILD   ?= 1
ARCHS   ?= $(shell uname -m)
MINOS   = 12.0

APP  = build/FireStudio Mixer.app
BIN  = $(APP)/Contents/MacOS/FireStudioMixer
ICNS = build/AppIcon.icns
SWIFT = Sources/RegisterMap.swift Sources/MixerModel.swift Sources/Controls.swift Sources/Presets.swift Sources/Views.swift

all: $(BIN)

build/fsfw-%.o: Sources/fsfw.c Sources/fsfw.h
	mkdir -p build
	clang -O2 -Wall -Wno-deprecated-declarations -arch $* -mmacosx-version-min=$(MINOS) -c Sources/fsfw.c -o $@

build/FireStudioMixer-%: build/fsfw-%.o $(SWIFT)
	swiftc -O -parse-as-library -target $*-apple-macosx$(MINOS) -import-objc-header Sources/fsfw.h \
	  $(SWIFT) $< -framework IOKit -framework CoreFoundation -o $@

$(ICNS): tools/make_icon.swift
	mkdir -p build/AppIcon.iconset
	swift tools/make_icon.swift build/icon_1024.png
	for s in 16 32 128 256 512; do \
	  sips -z $$s $$s build/icon_1024.png --out build/AppIcon.iconset/icon_$${s}x$${s}.png >/dev/null; \
	  d=$$((s*2)); sips -z $$d $$d build/icon_1024.png --out build/AppIcon.iconset/icon_$${s}x$${s}@2x.png >/dev/null; \
	done
	iconutil -c icns build/AppIcon.iconset -o $@

$(BIN): $(foreach a,$(ARCHS),build/FireStudioMixer-$(a)) Info.plist $(ICNS)
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	sed -e 's/__VERSION__/$(VERSION)/' -e 's/__BUILD__/$(BUILD)/' Info.plist > "$(APP)/Contents/Info.plist"
	cp $(ICNS) "$(APP)/Contents/Resources/AppIcon.icns"
	lipo -create $(foreach a,$(ARCHS),build/FireStudioMixer-$(a)) -output "$(BIN)"
	codesign --force -s - "$(APP)"
	@echo "Architectures : $$(lipo -archs "$(BIN)")"

pkg: all
	pkgbuild --component "$(APP)" --install-location /Applications \
	  --identifier io.github.opencontrol-firestudio.mixer --version $(VERSION) \
	  "build/OpenControl-FireStudio-$(VERSION)-app.pkg"

zip: all
	cd build && ditto -c -k --keepParent "FireStudio Mixer.app" "OpenControl-FireStudio-$(VERSION)-app.zip"

install: all
	-pkill -TERM -f "FireStudio Mixer.app/Contents/MacOS/FireStudioMixer"; sleep 1
	ditto "$(APP)" "/Applications/FireStudio Mixer.app"
	@echo "Installée : /Applications/FireStudio Mixer.app"

clean:
	rm -rf build

.PHONY: all pkg zip install clean
.SECONDARY:
