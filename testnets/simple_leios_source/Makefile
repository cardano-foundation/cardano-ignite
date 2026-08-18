.PHONY: all block blockperf build canary clean dbsync down ebperf example_zone help node_graph pools prerequisites prometheus_target query TESTNET up up-all validate yaci
.SILENT: all block blockperf build canary dbsync down ebperf pools prerequisites query up up-all validate yaci

# Required for builds on OSX ARM
export DOCKER_DEFAULT_PLATFORM?=linux/amd64

export DOCKER_BUILDKIT=1
export COMPOSE_DOCKER_CLI_BUILD=1

TESTNET=simple_leios_source
PROFILING ?= 0

# Determine and set the parent network interface
HOST_INTERFACE_SETUP = \
    if [ -z "$${HOST_INTERFACE+x}" ]; then \
        HOST_INTERFACE=$$(ip -br link show | awk '$$1 ~ /^dummy[0-9]*$$/ {print $$1; exit}') ; \
        [ -n "$$HOST_INTERFACE" ] || HOST_INTERFACE=$$(ip -br link show | awk '$$1 !~ /^lo$$|^vir|^wl/ && $$1 !~ /@/ {print $$1; exit}'); \
        [ -n "$$HOST_INTERFACE" ] || { \
            echo "Error: No suitable network interface found (loopback, wireless and virtual interfaces are skipped)."; \
            echo "Please create a dummy interface:"; \
            echo "  sudo ip link add dummy0 type dummy"; \
            echo "  sudo ip link set dummy0 up"; \
            echo "or select an interface explicitly: make <target> testnet=<testnet> HOST_INTERFACE=<interface>"; \
            exit 1; }; \
    fi && \
    export HOST_INTERFACE && \
    echo "Using HOST_INTERFACE=\"$$HOST_INTERFACE\""

TESTNET: ;
	@if [ -z "${testnet}" ]; then echo "* Please define the testnet argument:"; echo "testnet=simple_leios_source"; echo; exit 1; else export testnet=${testnet}; fi

# An existing .env.tmp is kept while the testnet has running containers or
# data volumes, so repeated 'make up' stays idempotent and a stopped testnet
# resumes with its original SYSTEM_START. Without either, the file is a stale
# leftover (e.g. from a 'make up' that failed the build check, or an
# interrupted 'make down') and is regenerated with a fresh SYSTEM_START.
.env.tmp: TESTNET
	@if [ -f $@ ]; then \
		if [ -n "$$(docker compose ps -q 2>/dev/null)" ] || \
		   [ -n "$$(docker volume ls -q --filter label=com.docker.compose.project=$* | head -1)" ]; then \
			exit 0; \
		fi; \
		echo "Regenerating stale .env.tmp for '$*' (no running containers or data volumes)"; \
	fi; \
	export SYSTEM_START=$$(date -u +'%Y-%m-%dT%H:%M:%SZ') \
	&& echo "SYSTEM_START=$${SYSTEM_START}" > .env.tmp \
	&& echo "TESTNET_BUILDER_IMAGE=$(TESTNET)-testnet_builder" >> .env.tmp \
	&& echo "HASKELL_BUILDER_IMAGE=$(TESTNET)-haskell_builder" >> .env.tmp \
	&& if [ "$${NO_INTERPOOL_LOCALROOTS+set}" = "set" ]; then \
		echo "NO_INTERPOOL_LOCALROOTS=$${NO_INTERPOOL_LOCALROOTS}" >> .env.tmp; \
	fi \
	&& if [ "$${PROFILING+set}" = "set" ]; then \
		echo "PROFILING=$${PROFILING}" >> .env.tmp; \
	fi \
	&& if [ "$${SHUTDOWN_ON_BLOCK+set}" = "set" ]; then \
		echo "SHUTDOWN_ON_BLOCK=$${SHUTDOWN_ON_BLOCK}" >> .env.tmp; \
	fi

up: TESTNET .env.tmp
	$(HOST_INTERFACE_SETUP) \
	&& echo "HOST_INTERFACE=$$HOST_INTERFACE" >> .env.tmp \
	&& echo "testnet=$$testnet" >> .env.tmp \
	&& docker compose --env-file .env.tmp --profile core up -d p1 p2 c1 loki grafana prometheus blackbox synth \
	&& bash init-forge-dir.sh \
	&& docker compose --env-file .env.tmp --profile core up -d p3
