# nocchi — common tasks. Run `make` or `make help` for the list.

CONFIG ?= debug
APP    := build/nocchi.app

.DEFAULT_GOAL := help
.PHONY: help build release test app run dev stop clean

help: ## Show this help
	@awk 'BEGIN {FS = ":.*## "} /^[a-z-]+:.*## / {printf "  \033[36m%-8s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

build: ## Compile (CONFIG=debug|release, default debug)
	swift build -c $(CONFIG)

release: ## Build a release nocchi.app
	scripts/bundle.sh release

test: ## Run all tests
	swift test

app: ## Build nocchi.app (CONFIG=debug|release)
	scripts/bundle.sh $(CONFIG)

run: app ## Build and launch nocchi.app
	-pkill -x nocchi
	open $(APP)

dev: ## Rebuild a debug bundle and relaunch it
	scripts/dev.sh

stop: ## Quit a running nocchi
	-pkill -x nocchi

clean: ## Remove build output
	swift package clean
	rm -rf build
