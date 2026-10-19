# With only the Command Line Tools installed, the macOS 27 SDK's SwiftUI `@State` macro has no
# plugin (it ships with Xcode), so build against the 26.x SDK instead. With Xcode, use its SDK.
CLT_SDK := /Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk
ifeq ($(shell xcode-select -p),/Library/Developer/CommandLineTools)
  ifneq ($(wildcard $(CLT_SDK)),)
    export SDKROOT := $(CLT_SDK)
  endif
endif

.PHONY: build run test app install clean

build:
	swift build

run:
	swift run DesktopEdit

# Pass FILTER=SuiteOrTestName to run a subset.
test:
	swift test $(if $(FILTER),--filter $(FILTER))

app:
	scripts/bundle.sh

# Copies the app to /Applications so Spotlight/Launchpad can find it (needed to reopen it
# when the menu bar icon and drop zone are both hidden).
install: app
	ditto build/DesktopEdit.app /Applications/DesktopEdit.app

clean:
	rm -rf .build build
