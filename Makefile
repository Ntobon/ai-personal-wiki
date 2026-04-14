SHELL := /bin/bash
.ONESHELL:
.DEFAULT_GOAL := help

DC := docker compose
PSQL := $(DC) exec -T db psql -U wiki -d wiki -v ON_ERROR_STOP=1

.PHONY: help up down reset migrate test psql logs wait

help:
	@echo "Targets:"
	@echo "  up       Start Postgres container (detached)"
	@echo "  down     Stop container (keep volume)"
	@echo "  reset    Stop + drop volume + restart clean"
	@echo "  migrate  Apply migrations/*.sql in order"
	@echo "  test     Run all tests/*.sql"
	@echo "  psql     Open psql shell"
	@echo "  logs     Tail db logs"

up:
	$(DC) up -d db
	@$(MAKE) --no-print-directory wait

wait:
	@echo "Waiting for Postgres to be healthy..."
	@for i in $$(seq 1 30); do
		status=$$($(DC) ps --format json db 2>/dev/null | grep -o '"Health":"[^"]*"' | head -1 | cut -d'"' -f4)
		if [ "$$status" = "healthy" ]; then echo "ready."; exit 0; fi
		sleep 1
	done
	@echo "Postgres did not become healthy in 30s"; exit 1

down:
	$(DC) down

reset:
	$(DC) down -v
	$(MAKE) --no-print-directory up
	$(MAKE) --no-print-directory migrate

migrate:
	@for f in migrations/*.sql; do
		name=$$(basename $$f)
		echo "→ applying $$name"
		$(PSQL) -f /migrations/$$name
	done

test:
	@bash scripts/run-tests.sh

psql:
	$(DC) exec db psql -U wiki -d wiki

logs:
	$(DC) logs -f db
