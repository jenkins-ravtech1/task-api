# =============================================================================
# Tasks API — convenience commands
# Run `make help` to list available targets.
#
# Note: Make recipe lines are indented with a TAB, not spaces.
# =============================================================================

.DEFAULT_GOAL := help
.PHONY: help build test run clean image compose-up compose-down \
        ecr-push tf-init tf-plan tf-apply destroy

# Images target the EC2/CI architecture (linux/amd64).
PLATFORM := linux/amd64
IMAGE := tasks-api:local
COMPOSE := docker compose -f docker/docker-compose.yml
AWS_REGION ?= eu-central-1

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

# --- AWS (require credentials + a terraform-applied stack) -------------------

ecr-push: image ## Build & push the image to ECR, tagged with the git SHA + latest (manual deploy; CD automates this)
	@ECR_URL=$$(terraform -chdir=infra output -raw ecr_repository_url); \
	TAG=$$(git rev-parse --short HEAD); \
	REGISTRY=$${ECR_URL%%/*}; \
	aws ecr get-login-password --region $(AWS_REGION) | docker login --username AWS --password-stdin $$REGISTRY; \
	docker tag $(IMAGE) $$ECR_URL:$$TAG; \
	docker tag $(IMAGE) $$ECR_URL:latest; \
	docker push $$ECR_URL:$$TAG; \
	docker push $$ECR_URL:latest; \
	echo "Pushed $$ECR_URL:$$TAG (and :latest)"

tf-init: ## terraform init (pass -backend-config via runbook; see docs/runbook.md)
	terraform -chdir=infra init

tf-plan: ## terraform plan
	terraform -chdir=infra plan

tf-apply: ## terraform apply
	terraform -chdir=infra apply

destroy: ## Tear down ALL AWS resources (cost safety)
	terraform -chdir=infra destroy
