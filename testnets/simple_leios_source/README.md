# Description

Leios (Ouroboros Leios) testnet: hard-forks to the Dijkstra era at genesis and forges
endorser blocks. Built from source, mirroring the official ouroboros-leios testnet node
config. Endorser blocks only appear under transaction load, so start the tx-generator with
`make up-all`. Ships a Leios-aware cardano-db-sync (built from source) and a Leios Grafana
dashboard scoped to this testnet.

## Cardano-Node

- **Version**: 11.0.1.164
- **Branch**: leios-prototype (db5373ea6)
- **Binary/Source**: Source

## Testnet

- **Pools**: 3
