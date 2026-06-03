
## 0.2.0 -- 2026-06-03


### Added

- Support for cardano-node 10.7.2
- Support for cardano-node 11.0.1
- Added support for profiling of cardano-nodes. Requires PROFILING=1 and SHUTDOWN_ON_BLOCK=<some block>
- New global_network_2c testnet for bechmarking or A/B testing.
- Support specifying TxSubmissionLogic version for cardano-node.
- Added support for specifying target nodes for tx-generator with TX_GENERATOR_TARGETS
- Mempool Bytes panel
- Mempool Fullness panel
- Tx Acceptance Rate panel
- cardano-node cpu panel
- GC Pause time panel

### Changed

- Postgresql now binds to 127.0.0.1:5432 by default. Change with PSQL_HOST and PSQL_PORT.
- Grafana now binds to 127.0.0.1:5432 by default. Change with GRAFANA_HOST and GRAFANA_PORT.
- Loki now binds to 127.0.0.1:3100 by default. Change with LOKI_HOST and LOKI_PORT.
- Delay canary start by 120s
- Specify profiling details for all packages
- Wait 60s before starting tx-generator.
- Bump timeout for bringing down containers from 1s to 5s.
- cardano-nodes start depends on gateway nodes in fancy topologies
- make all now reports testnets that fail to build
- Changed cardano-node to use the new tracing subsystem.

### Updated

- Update Blockfrost from 6.4.0 to 6.4.3
- Update Cardano CLI from 10.15.1.0 to 11.0.0.0
- Update Cardano DB Sync from 13.6.0.4 to 13.7.1.0
- Update Cardano TX Generator from 10.6.4 to 11.0.1
- Update Debian from stable-20260421-slim to stable-20260518-slim
- Update Grafana from 13.0.1 to 13.0.2
- Update Jaeger from 2.17.0 to 2.18.0
- Update Loki from 3.7.1 to 3.7.2
- Update PostgreSQL from 17.9 to 17.10
- Update Prometheus from 3.11.2 to 3.12.0
- Update Yaci Store from 2.0.0 to 2.0.1
- Update uv from 0.11.7 to 0.11.18
- Update Blockfrost from v5.0.0 to v6.2.0
- Update Debian from stable-20260112-slim to stable-20260223-slim
- Update Grafana from 12.3.1 to 12.4.0
- Update Jaeger from 2.14.1 to 2.15.1
- Update Loki from 3.6.4 to 3.6.7
- Update PostgreSQL from 17.7 to 17.9
- Update Prometheus from v3.9.1 to v3.10.0
- Update Yaci Store from v2.0.0-beta5 to v2.0.0
- Update uv from 0.9.27 to 0.10.8
- Update yq from v4.50.1 to v4.52.4
- Bump cardano-node 10.6.2 nodes to 10.6.4
- Bump cardano-node 10.7.0 nodes to 10.7.1
- Update Blockfrost from 6.2.0 to 6.4.0
- Update Cardano TX Generator from 10.5.4 to 10.6.4
- Update Cardano-CLI from 10.11.1.0 to 10.15.1.0
- Update CoreDNS from 1.14.1 to 1.14.3
- Update Debian from stable-20260223-slim to stable-20260421-slim
- Update Grafana from 12.4.0 to 13.0.1
- Update Jaeger from 2.15.1 to 2.17.0
- Update Loki from 3.6.7 to 3.7.1
- Update Prometheus from 3.10.0 to 3.11.2
- Update uv from 0.10.8 to 0.11.7
- Update ya from 4.52.4 to 4.53.2

### Fixed

- Fix docker InvalidDefaultArgInFrom warnings
- Don't build profiling cardano-node binaries by default
- Fixed blockperf.sh so that it handled the updated log format
- Set default value for TX_SUBMISSION_LOGIC_VERSION
- Have globa_network_2c use the standard gateway/scripts/gw_routes.sh script
- down target, clean up any orphan containers and interfaces we created
- Copy genesis files from synth to prevent missmatch between different cardano-node versions.
- Fixed simple_mixed_consensus docker compose file.
- Fix race condition between gateways

## 0.1.2 -- 2026-02-10

### Updated

- Updated cardano-node 10.5.3 instances to 10.5.4

### Fixed

- Workaround for SHA-1 preimage nodejs issue

## 0.1.1 -- 2026-01-28

### Added

- Add CHANGELOG.md file

### Updated

- Update Blackbox Exporter from v0.27.0 to v0.28.0
- Update Blockfrost from 4.3.0 to 5.0.0
- Update CoreDNS from 1.13.1 to 1.14.1
- Update Debian from stable-20251117-slim to stable-20260112-slim
- Update Grafana from 12.3.0 to 12.3.2
- Update Jaeger from 2.12.0 to 2.14.1
- Update Loki from 3.6.2 to 3.6.4
- Update Prometheus from v3.7.3 to v3.9.1
- Update uv from 0.9.13 to 0.9.27
- Update ya from v4.49.2 to v4.50.1

## 0.1.0 -- 2026-01-23

- First version. Released on an unsuspecting world.
