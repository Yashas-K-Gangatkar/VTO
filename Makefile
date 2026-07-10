.PHONY: dev dev-down test lint build migrate seed clean fmt install bootstrap scaffold-services

# Default target
.DEFAULT_GOAL := help

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

install: ## Install dependencies
	pnpm install
	@for dir in apps/*/; do \
		if [ -f "$$dir/go.mod" ]; then \
			(cd $$dir && go mod download); \
		fi; \
	done
	@if [ -f "ai/pyproject.toml" ]; then \
		(cd ai && pip install -e .); \
	fi

dev: ## Start full local stack via Docker Compose
	cd infrastructure/docker && docker compose up -d
	@echo "Stack starting. Healthcheck at http://localhost:8080/v1/health"
	@echo "Wait ~30 seconds for all services to be ready."

dev-down: ## Stop the local stack
	cd infrastructure/docker && docker compose down

test: ## Run all unit tests
	pnpm test
	@for dir in apps/*/; do \
		if [ -f "$$dir/go.mod" ]; then \
			echo "Testing $$dir"; \
			(cd $$dir && go test ./...); \
		fi; \
	done

lint: ## Lint all code
	pnpm lint
	@for dir in apps/*/; do \
		if [ -f "$$dir/go.mod" ]; then \
			echo "Linting $$dir"; \
			(cd $$dir && go vet ./...); \
		fi; \
	done

build: ## Build all services and packages
	pnpm build
	@for dir in apps/*/; do \
		if [ -f "$$dir/go.mod" ]; then \
			echo "Building $$dir"; \
			(cd $$dir && go build -o bin/service ./cmd/server); \
		fi; \
	done

migrate: ## Apply database migrations
	@for dir in apps/*/; do \
		if [ -d "$$dir/migrations" ]; then \
			echo "Migrating $$dir"; \
			(cd $$dir && migrate -path migrations -database "postgres://vto:vto@localhost:5432/vto?sslmode=disable" up); \
		fi; \
	done

seed: ## Seed local database with test data
	./infrastructure/scripts/seed-local-db.sh

clean: ## Remove build artifacts
	rm -rf node_modules apps/*/bin apps/*/dist packages/*/dist dashboard/.next
	@for dir in apps/*/; do \
		if [ -f "$$dir/go.mod" ]; then \
			(cd $$dir && go clean); \
		fi; \
	done

fmt: ## Format all code
	pnpm exec prettier --write "**/*.{ts,tsx,js,jsx,json,md,yaml,yml}"
	@for dir in apps/*/; do \
		if [ -f "$$dir/go.mod" ]; then \
			(cd $$dir && go fmt ./...); \
		fi; \
	done

bootstrap: ## Initialize git hooks and verify setup
	pnpm exec husky install
	@echo "Bootstrap complete. Run 'make dev' to start."

scaffold-services: ## Create scaffolds for all backend services (idempotent)
	./tools/scaffold-services.sh
