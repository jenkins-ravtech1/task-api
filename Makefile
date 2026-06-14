# =============================================================================
# Tasks API — convenience commands
# Run `make help` to list available targets.
#
# Note: Make recipe lines are indented with a TAB, not spaces.
# =============================================================================

.DEFAULT_GOAL := help
.PHONY: help build test run clean image compose-up compose-down

# Images target the EC2/CI architecture (linux/amd64).
PLATFORM := linux/amd64
IMAGE := tasks-api:local
COMPOSE := docker compose -f docker/docker-compose.yml

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

image: ## Build the Docker image (linux/amd64)
	docker build --platform $(PLATFORM) -f docker/Dockerfile -t $(IMAGE) .

compose-up: ## Run the full local stack (app + LocalStack) in the foreground
	@# Build the lambda jar on the host first so LocalStack can deploy it.
	mvn -q -pl lambda -am package -DskipTests
	$(COMPOSE) up --build

compose-down: ## Stop the local stack and remove its containers/volumes
	$(COMPOSE) down -v
