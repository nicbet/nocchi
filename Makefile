# nocchi — common tasks. Run `make` or `make help` for the list.

CONFIG ?= debug
APP    := build/Nocchi.app

.DEFAULT_GOAL := help
.PHONY: help build release install test app run dev stop snapshot live icon signing-cert reset-permissions clean

help: ## Show this help
	@awk 'BEGIN {FS = ":.*## "} /^[a-z-]+:.*## / {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

build: ## Compile (CONFIG=debug|release, default debug)
	swift build -c $(CONFIG)

release: ## Build a release Nocchi.app
	scripts/bundle.sh release

install: release ## Build a release Nocchi.app and copy it to /Applications
	-pkill -x nocchi
	rm -rf /Applications/Nocchi.app
	ditto $(APP) /Applications/Nocchi.app
	@echo "Installed /Applications/Nocchi.app"

test: ## Run all tests (Herdr integration tests run when herdr is installed)
	swift test

app: ## Build Nocchi.app (CONFIG=debug|release)
	scripts/bundle.sh $(CONFIG)

run: app ## Build and launch Nocchi.app
	-pkill -x nocchi
	open $(APP)

dev: ## Rebuild a debug bundle and relaunch it
	scripts/dev.sh

stop: ## Quit a running nocchi
	-pkill -x nocchi

snapshot: build ## Render the notch in each mode to build/snapshots/*.png
	$$(swift build -c $(CONFIG) --show-bin-path)/nocchi --snapshot build/snapshots

live: build ## Render the notch from the real Herdr to build/snapshots/live-*.png
	$$(swift build -c $(CONFIG) --show-bin-path)/nocchi --snapshot build/snapshots --live

icon: ## Re-render Resources/AppIcon.icns from the icon design (AppIcon.swift)
	scripts/make-icon.sh

signing-cert: ## Create the local signing certificate so permissions survive rebuilds
	scripts/create-signing-cert.sh

reset-permissions: ## Reset Nocchi's Accessibility grant
	tccutil reset Accessibility com.github.nicbet.nocchi

clean: ## Remove build output
	swift package clean
	rm -rf build
