GHOSTTY_DIR ?= $(HOME)/ghostty

SWIFT_BUILD_FLAGS = \
	-Xlinker -L$(GHOSTTY_DIR)/zig-out/lib \
	-Xlinker -lghostty \
	-Xlinker -lc++ \
	-Xlinker -framework -Xlinker Metal \
	-Xlinker -framework -Xlinker Foundation \
	-Xlinker -framework -Xlinker CoreGraphics \
	-Xlinker -framework -Xlinker CoreText \
	-Xlinker -framework -Xlinker QuartzCore \
	-Xlinker -framework -Xlinker IOKit \
	-Xlinker -framework -Xlinker IOSurface

.PHONY: build run release bundle clean

build:
	swift build $(SWIFT_BUILD_FLAGS)

run: build
	.build/debug/Ghostlight

release:
	swift build -c release $(SWIFT_BUILD_FLAGS)

bundle: release
	@mkdir -p Ghostlight.app/Contents/MacOS
	@mkdir -p Ghostlight.app/Contents/Resources
	@cp Info.plist Ghostlight.app/Contents/
	@cp .build/release/Ghostlight Ghostlight.app/Contents/MacOS/
	@echo "Created Ghostlight.app"

clean:
	swift package clean
	rm -rf Ghostlight.app
