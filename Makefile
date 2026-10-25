# With only the Command Line Tools installed, the macOS 27 SDK's SwiftUI `@State` macro has no
# plugin (it ships with Xcode), so build against the 26.x SDK instead. With Xcode, use its SDK.
CLT_SDK := /Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk
ifeq ($(shell xcode-select -p),/Library/Developer/CommandLineTools)
  ifneq ($(wildcard $(CLT_SDK)),)
    export SDKROOT := $(CLT_SDK)
  endif
endif

# `make dmg VERSION=1.2.3` stamps the bundle and names the DMG.
VERSION ?= 0.1.0
export VERSION

.PHONY: build run test app dmg install clean

build:
	swift build

run:
	swift run Dropsmith

# Pass FILTER=SuiteOrTestName to run a subset.
test:
	swift test $(if $(FILTER),--filter $(FILTER))

app:
	scripts/bundle.sh

# Drag-to-install disk image at build/Dropsmith-$(VERSION).dmg.
dmg: app
	scripts/dmg.sh

# Copies the app to /Applications so Spotlight/Launchpad can find it (needed to reopen it
# when the menu bar icon and drop zone are both hidden).
install: app
	ditto build/Dropsmith.app /Applications/Dropsmith.app

clean:
	rm -rf .build build
