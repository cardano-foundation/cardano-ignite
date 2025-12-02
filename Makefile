.PHONY: all clean example_zone node_graph prerequisites prometheus_target
.SILENT: all block build dbsync down pools prerequisites query up up-all validate yaci

# Required for builds on OSX ARM
export DOCKER_DEFAULT_PLATFORM?=linux/amd64

export COMPOSE_PARALLEL_LIMIT=1
export DOCKER_BUILDKIT=1
export COMPOSE_DOCKER_CLI_BUILD=1

# Determine and set the parent network interface
HOST_INTERFACE_SETUP = \
    if [ -z "$${HOST_INTERFACE+x}" ]; then \
        HOST_INTERFACE=$$(ip -br link show | awk '$$1 ~ /^dummy[0-9]*$$/ {print $$1; exit}') ; \
        [ -n "$$HOST_INTERFACE" ] || HOST_INTERFACE=$$(ip -br link show | awk '$$1 !~ /^lo$$|^vir|^wl/ && $$1 !~ /@/ {print $$1; exit}'); \
        [ -n "$$HOST_INTERFACE" ] || { echo "No physical interface found"; exit 1; }; \
    fi && \
    export HOST_INTERFACE && \
    echo "Using HOST_INTERFACE=\"$$HOST_INTERFACE\""

help:
	@echo
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[34m%-30s\033[0m %s\n", $$1, $$2}'
	@echo
	@echo "Arguments:"
	@printf "  \033[34m%-30s\033[0m %s\n" testnet "Testnet directory name (Example: simple_network_binary)"
	@echo
	@echo "Examples:"
	@printf "  \033[34mBuild and Start\033[0m\n"
	@echo "    make build testnet=simple_network_binary"
	@echo "    make up testnet=simple_network_binary"
	@echo
	@printf "  \033[34m Query and Verify\033[0m\n"
	@echo "    make block"
	@echo "    make dbsync"
	@echo "    make pools"
	@echo "    make query testnet=simple_network_binary"
	@echo "    make validate"
	@echo
	@printf "  \033[34mStop and Destroy\033[0m\n"
	@echo "    make down testnet=simple_network_binary"
	@echo

prerequisites:
	@command -v yq >/dev/null 2>&1 || { \
		echo "Error: yq is not installed."; \
		echo "Please install the mikefarah yq binary from https://github.com/mikefarah/yq/releases/"; \
		exit 1; \
	}
	@yq --version 2>&1 | grep -q "mikefarah" || { \
		echo "Error: The installed yq is not the mikefarah variant."; \
		echo "Please uninstall the current yq and fetch the right yq binary from https://github.com/mikefarah/yq/releases/"; \
		exit 1; \
	}
	docker plugin ls | grep 'loki' >/dev/null 2>&1 || docker plugin install grafana/loki-docker-driver --alias loki --grant-all-permissions

node_graph: TESTNET testnets/${testnet}/graph_nodes.sql

testnets/%/graph_nodes.sql: scripts/graph_node.sh testnets/%/docker-compose.yaml
	./scripts/graph_node.sh testnets/$*/docker-compose.yaml >$@

example_zone: TESTNET testnets/${testnet}/coredns/example.zone

testnets/%/coredns/example.zone: scripts/ns_zone.sh testnets/%/docker-compose.yaml
	mkdir -p testnets/${testnet}/coredns
	./scripts/ns_zone.sh testnets/$*/docker-compose.yaml testnets/$*/coredns

prometheus_target: TESTNET testnets/${testnet}/prometheus/prometheus.yml

testnets/%/prometheus/prometheus.yml: scripts/prometheus_targets.sh testnets/%/docker-compose.yaml
	mkdir -p testnets/${testnet}/prometheus/
	./scripts/prometheus_targets.sh testnets/$*/docker-compose.yaml >$@

testnets/%/.env.tmp: TESTNET
	export SYSTEM_START=$$(date -u +'%Y-%m-%dT%H:%M:%SZ') \
	&& echo "SYSTEM_START=$${SYSTEM_START}" > testnets/$*/.env.tmp \
	&& if [ "$${NO_INTERPOOL_LOCALROOTS+set}" = "set" ]; then \
		echo "NO_INTERPOOL_LOCALROOTS=$${NO_INTERPOOL_LOCALROOTS}" >> testnets/$*/.env.tmp; \
	fi

buildx: TESTNET prerequisites testnets/${testnet}/graph_nodes.sql testnets/${testnet}/coredns/example.zone testnets/${testnet}/prometheus/prometheus.yml ## Build testnet
	ln -snf testnets/${testnet}/testnet.yaml .testnet.yaml && \
	$(HOST_INTERFACE_SETUP) && \
	mkdir -p .buildx-cache && \
	if ! docker network inspect buildkit-net >/dev/null 2>&1; then \
		docker network create buildkit-net; \
	fi && \
	if ! docker ps | grep -q 'buildkit-registry'; then \
		docker run -d --restart=always --network buildkit-net --name buildkit-registry registry:2; \
	fi && \
	if ! docker buildx inspect buildx-builder >/dev/null 2>&1; then \
		docker buildx create --name buildx-builder \
			--driver docker-container \
			--config ./buildkitd.toml \
			--driver-opt network=buildkit-net \
			--use; \
	else \
		docker buildx use buildx-builder; \
	fi && \
	normalized_testnet=$$(echo ${testnet} | sed -E 's/[^a-zA-Z0-9.-]+/-/g' | tr 'A-Z' 'a-z') && \
	docker buildx build \
		--cache-from type=local,src=.buildx-cache \
		--cache-to type=local,dest=.buildx-cache,mode=max \
		-t buildkit-registry:5000/$${normalized_testnet}-testnet-builder:latest \
		-f testnet-generation-tool/Dockerfile \
		--push . && \
	docker buildx build \
		--cache-from type=local,src=.buildx-cache \
		--cache-to type=local,dest=.buildx-cache,mode=max \
		-t buildkit-registry:5000/$${normalized_testnet}-haskell-builder:latest \
		-f haskell-builder/Dockerfile \
		--push . && \
	cd testnets/${testnet} && \
	DOCKER_BUILDKIT=1 COMPOSE_DOCKER_CLI_BUILD=1 \
	docker compose --profile build build \
		--build-arg GRAPHNODES="testnets/${testnet}/graph_nodes.sql" \
		--build-arg TESTNET_BUILDER_IMAGE="buildkit-registry:5000/$${normalized_testnet}-testnet-builder:latest" \
		--build-arg HASKELL_BUILDER_IMAGE="buildkit-registry:5000/$${normalized_testnet}-haskell-builder:latest"

build: TESTNET prerequisites testnets/${testnet}/graph_nodes.sql testnets/${testnet}/coredns/example.zone testnets/${testnet}/prometheus/prometheus.yml ## Build testnet
	ln -snf testnets/${testnet}/testnet.yaml .testnet.yaml && \
	$(HOST_INTERFACE_SETUP) && \
	docker build -t ${testnet}-testnet_builder -f testnet-generation-tool/Dockerfile . && \
	docker build -t ${testnet}-haskell_builder -f haskell-builder/Dockerfile . && \
	cd testnets/${testnet} && \
	docker compose --profile build build --parallel=false --no-parallel --build-arg GRAPHNODES="testnets/${testnet}/graph_nodes.sql" --build-arg TESTNET_BUILDER_IMAGE="${testnet}-testnet_builder" --build-arg HASKELL_BUILDER_IMAGE="${testnet}-haskell_builder"

cibuild: TESTNET prerequisites testnets/${testnet}/graph_nodes.sql testnets/${testnet}/coredns/example.zone testnets/${testnet}/prometheus/prometheus.yml ## Build testnet
	ln -snf testnets/${testnet}/testnet.yaml .testnet.yaml && \
	$(HOST_INTERFACE_SETUP) && \
	docker buildx create --use && \
	docker buildx build -t ${testnet}-testnet_builder -f testnet-generation-tool/Dockerfile --load . && \
	docker buildx build -t ${testnet}-haskell_builder -f haskell-builder/Dockerfile --load . && \
	docker buildx use default && \
	cd testnets/${testnet} && \
	docker compose --profile build build --build-arg GRAPHNODES="testnets/${testnet}/graph_nodes.sql" --build-arg TESTNET_BUILDER_IMAGE="${testnet}-testnet_builder" --build-arg HASKELL_BUILDER_IMAGE="${testnet}-haskell_builder"



all:
	for dir in testnets/*; do \
		if [ -d "$${dir}" ]; then \
			$(MAKE) build testnet=$$(basename $${dir}); \
		fi; \
	done

up: TESTNET testnets/${testnet}/.env.tmp ## Start testnet without optional containers
	cd testnets/${testnet} && \
	$(HOST_INTERFACE_SETUP) && \
	echo "HOST_INTERFACE=$$HOST_INTERFACE" >> .env.tmp && \
	echo "testnet=$$testnet" >> .env.tmp && \
	docker compose --env-file .env.tmp --profile core up --detach

up-all: TESTNET ## Start testnet with optional containers (Blockfrost, TX Generator...)
	@if [ ! -f testnets/${testnet}/.env.tmp ]; then \
		$(MAKE) up testnet=${testnet}; \
	fi
	cd testnets/${testnet} && \
	docker compose --env-file .env.tmp --profile optional --profile privaterelays up --detach

down: TESTNET ## Stop testnet
	@cd testnets/${testnet} && \
	docker compose --env-file .env.tmp --profile core --profile optional --profile privaterelays down --volumes --timeout 1 && \
	rm -f .env.tmp

query: TESTNET ## Query tip of all pools
	pools="$$(awk '/container_name: /{ print $$2 }' testnets/${testnet}/docker-compose.yaml | grep -E '^p[0-9][a-zA-Z0-9]*$$')" ; \
	for i in $${pools} ; do docker exec -ti $${i} timeout 0.05 cardano-cli ping --magic 42 --host 127.0.0.1 --port 3001 --tip --quiet -c1; done ; true ; \
	echo '# client' ; \
	docker exec -ti c1 timeout 0.05 cardano-cli ping --magic 42 --host 127.0.0.1 --port 3001 --tip --quiet -c1 ; true

validate: ## Check for consensus among all pools
	docker exec sidecar /opt/scripts/eventually_converged.sh

dbsync: ## Run SQL query in cardano-db-sync
	docker exec -ti dbsync /usr/bin/psql --host db.example --dbname dbsync --user dbsync --command="SELECT time,block_no,slot_no FROM block WHERE block_no=(SELECT MAX(block_no) FROM block);"

yaci: ## Run SQL query in yaci-store
	docker exec -ti sidecar /usr/bin/psql --host db.example --dbname yaci --user yaci --command="SELECT to_timestamp(block_time),number,slot FROM block WHERE number=(SELECT MAX(number) FROM block);"


block: ## Run Blockfrost query on '/blocks/latest'
	docker exec -ti blockfrost curl http://127.0.0.1:3000/blocks/latest | jq

pools: ## Run Blockfrost query on '/pools/extended'
	docker exec -ti blockfrost curl --silent http://127.0.0.1:3000/pools/extended | jq

TESTNET: ;
	@if [ -z "${testnet}" ]; then echo "* Please define the testnet argument:"; echo "testnet=simple_network_binary"; echo; exit 1; else export testnet=${testnet}; fi

clean:
	rm -f .testnet.yaml
	rm -f testnets/*/graph_nodes.sql
	rm -rf testnets/*/.env.tmp
	rm -rf testnets/*/coredns
	rm -rf testnets/*/prometheus
