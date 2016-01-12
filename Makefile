# Is there a better way to do this? (kevsmith 12/4/2015)
GENERATED_FILES := deps/piper/lib/piper/permissions/piper_rule_lexer.erl \
		   deps/piper/lib/piper/permissions/piper_rule_parser.erl

.DEFAULT_GOAL := run

ifdef BUILDKITE_BUILD_NUMBER
# TEST_DATABASE_URL is set in Buildkite; it points to an Amazon RDS
# PostgreSQL instance we use
TEST_DATABASE_URL := $(TEST_DATABASE_URL).$(BUILDKITE_BUILD_NUMBER)
endif

ci: export DATABASE_URL = $(TEST_DATABASE_URL)
ci: export MIX_ENV = test
ci: ci-setup test-all ci-cleanup

ci-reset:
	@echo "Resetting build environment"
	@rm -rf _build

ci-setup: ci-reset
# Nuke mnesia dirs so we don't get borked on emqttd upgrades
	rm -rf Mnesia.* $(GENERATED_FILES)
	mix deps.get

ci-cleanup:
	mix ecto.drop

# Note: 'run' does not reset the database, in case you have data
# you're actively using. If this is your first time, run `make
# reset-db` before executing this recipe.
run:
	iex --sname cog_dev@localhost -S mix phoenix.server

reset-db:
	mix ecto.reset

test-rollbacks: export MIX_ENV = test
test-rollbacks: reset-db
	mix do ecto.rollback --all, ecto.drop

test: export MIX_ENV = test
test: reset-db
	mix test $(TEST)

test-all: export MIX_ENV = test
test-all: reset-db
	mix test \
		--include slack \
		--include hipchat

test-watch: export MIX_ENV = test
test-watch: reset-db
	mix test.watch $(TEST)

.PHONY: ci ci-setup ci-cleanup test
