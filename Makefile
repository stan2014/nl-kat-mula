SHELL := bash
.ONESHELL:
.SHELLFLAGS := -eu -o pipefail -c
.DELETE_ON_ERROR:
MAKEFLAGS += --warn-undefined-variables
MAKEFLAGS += --no-builtin-rules
# Makefile Reference: https://tech.davis-hansson.com/p/make/

.PHONY: help mypy check black done lint env

# use HIDE to run commands invisibly, unless VERBOSE defined
HIDE:=$(if $(VERBOSE),,@)

BYTES_VERSION= v0.6.0

# Export cmd line args:
export VERBOSE
export m
export build
export file

# Export Docker buildkit options
export DOCKER_BUILDKIT=1
export COMPOSE_DOCKER_CLI_BUILD=1

help: ## Show this help.
	@fgrep -h "##" $(MAKEFILE_LIST) | fgrep -v fgrep | sed -e 's/\\$$//' | sed -e 's/ ##/			/' | sed -e 's/##//'

check: ## Check the code style using black, mypy and pylint.
	make black
	make mypy
	make pylint

mypy: ## Check code style using mypy.
	docker-compose -f base.yml -f .ci/docker-compose.yml \
		run --rm mula \
		python -m mypy --cache-dir /home/scheduler/.mypy_cache /app/scheduler/scheduler

black: ## Check code style with black.
	docker-compose -f base.yml -f .ci/docker-compose.yml \
		run --rm mula \
		black --check --diff .

pylint: ## Rate the code with pylint.
	docker-compose -f base.yml -f .ci/docker-compose.yml \
		run --rm mula \
		pylint --rcfile pyproject.toml scheduler

fmt: ## Format the code using black.
	docker-compose -f base.yml -f .ci/docker-compose.yml \
		run --rm mula \
		black .

done: ## Prepare for a commit.
	make lint
	make check
	make test

sql: ## Generate raw sql for the migrations.
	docker-compose exec scheduler \
		alembic \
		--config /app/scheduler/alembic.ini \
		upgrade $(rev1):$(rev2) --sql

migrations: ## Create migration.
ifeq ($(m),)
	$(HIDE) (echo "ERROR: Specify a message with m={message} and a rev-id with revid={revid} (e.g. 0001 etc.)"; exit 1)
else ifeq ($(revid),)
	$(HIDE) (echo "ERROR: Specify a message with m={message} and a rev-id with revid={revid} (e.g. 0001 etc.)"; exit 1)
else
	docker-compose \
		run scheduler \
		alembic --config /app/scheduler/alembic.ini \
		revision --autogenerate \
		-m "$(m)" --rev-id "$(revid)"
endif

migrate: ## Run migrations using alembic.
	docker-compose \
		run scheduler \
		alembic --config /app/scheduler/alembic.ini \
		upgrade head


##
##|------------------------------------------------------------------------|
##			Tests
##|------------------------------------------------------------------------|

utest: ## Run the unit tests.
ifneq ($(build),)
	docker-compose -f base.yml -f .ci/docker-compose.yml build mula
endif

ifneq ($(file),)
	docker-compose -f base.yml  -f .ci/docker-compose.yml \
		run --rm mula python -m unittest tests/unit/${file} ${function}; \
	docker-compose -f base.yml  -f .ci/docker-compose.yml down
else
	docker-compose -f base.yml  -f .ci/docker-compose.yml \
		run --rm mula python -m unittest discover tests/unit; \
	docker-compose -f base.yml  -f .ci/docker-compose.yml down
endif

itest: ## Run the integration tests.
ifneq ($(build),)
	docker-compose -f base.yml -f .ci/docker-compose.yml build mula_integration
endif

ifneq ($(file),)
	docker-compose -f base.yml  -f .ci/docker-compose.yml \
		run --rm mula_integration python -m unittest -v tests/integration/${file} ${function}; \
	docker-compose -f base.yml  -f .ci/docker-compose.yml down
else
	docker-compose -f base.yml  -f .ci/docker-compose.yml \
		run --rm mula_integration python -m unittest discover -v tests/integration; \
	docker-compose -f base.yml  -f .ci/docker-compose.yml down
endif

stest: ## Run the simulation tests.
	docker-compose -f base.yml  -f .ci/docker-compose.yml \
		run --rm mula python -m unittest discover -v tests/simulation; \
	docker-compose -f base.yml  -f .ci/docker-compose.yml down

test: ## Run all tests.
	make utest
	make itest
