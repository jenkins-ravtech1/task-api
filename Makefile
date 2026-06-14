# =============================================================================
# Tasks API — convenience commands
# Run `make help` to list available targets.
#
# Note: Make recipe lines are indented with a TAB, not spaces.
# =============================================================================

.DEFAULT_GOAL := help
.PHONY: help build test run clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

build: ## Build the runnable (shaded) jar
	mvn -q -pl app -am package

test: ## Run unit tests (mvn verify)
	mvn -q -pl app -am verify

run: build ## Build then run the API locally in memory mode (http://localhost:8080)
	@# The shaded jar carries its version in the name (app-<ver>-shaded.jar),
	@# so resolve it with a glob at run time.
	java -jar $$(ls app/target/*-shaded.jar | head -n1)

clean: ## Remove build output (target/)
	mvn -q clean
