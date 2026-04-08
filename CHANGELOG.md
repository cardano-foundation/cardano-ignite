
## 0.1.3 -- 2026-03-26


### Added

- Added support for profiling of cardano-nodes. Requires PROFILING=1 and SHUTDOWN_ON_BLOCK=<some block>
- Support for cardano-node 10.7.0

### Changed

- Let global_network's p2 pool use cardano-node version 10.6.2
- Postgresql now binds to 127.0.0.1:5432 by default. Change with PSQL_HOST and PSQL_PORT.
- Grafana now binds to 127.0.0.1:5432 by default. Change with GRAFANA_HOST and GRAFANA_PORT.
- Loki now binds to 127.0.0.1:3100 by default. Change with LOKI_HOST and LOKI_PORT.

### Updated

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

### Fixed

- Fix docker InvalidDefaultArgInFrom warnings

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
