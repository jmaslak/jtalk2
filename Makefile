APP     := jtalk2
BUNDLE  := build/$(APP).app
ARCH    := $(shell uname -m)
MINOS   := 13.0
SWIFTC  := swiftc -target $(ARCH)-apple-macos$(MINOS)

ICON    := build/$(APP).icns
SOURCES := $(wildcard Sources/*.swift)
# Everything except the app's own entry point, so the tests can supply theirs.
LIB     := $(filter-out Sources/main.swift,$(SOURCES))

.PHONY: all run test icon clean install

all: $(BUNDLE)

$(BUNDLE): $(SOURCES) Info.plist $(ICON)
	@mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources
	$(SWIFTC) -O -o $(BUNDLE)/Contents/MacOS/$(APP) $(SOURCES)
	cp Info.plist $(BUNDLE)/Contents/Info.plist
	cp $(ICON) $(BUNDLE)/Contents/Resources/$(APP).icns
	codesign --force --sign - $(BUNDLE)
	@touch $(BUNDLE)

# The icon is drawn by a program rather than stored as a binary blob.
$(ICON): Tools/makeicon.swift
	@mkdir -p build
	$(SWIFTC) -o build/makeicon Tools/makeicon.swift
	build/makeicon build/$(APP).iconset
	iconutil -c icns -o $@ build/$(APP).iconset

icon: $(ICON)

run: $(BUNDLE)
	open $(BUNDLE)

# Both suites speak out loud, so they take about a minute.
test: build/test-speech build/test-ui
	build/test-speech
	build/test-ui

build/test-speech: $(LIB) Tests/speech/main.swift
	@mkdir -p build
	$(SWIFTC) -o $@ Sources/Speech.swift Sources/Pronunciations.swift Sources/KeyClick.swift \
		Tests/speech/main.swift

build/test-ui: $(LIB) Tests/ui/main.swift
	@mkdir -p build
	$(SWIFTC) -o $@ $(LIB) Tests/ui/main.swift

install: $(BUNDLE)
	@mkdir -p $(HOME)/Applications
	rm -rf $(HOME)/Applications/$(APP).app
	cp -R $(BUNDLE) $(HOME)/Applications/
	@echo "Installed to $(HOME)/Applications/$(APP).app"

clean:
	rm -rf build
