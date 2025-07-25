# cardano-ignite

## Index

- [Information](#information)
  - [Showcase](#showcase)
  - [Target Audience](#target-audience)
  - [Tech Stack](#tech-stack)
- [Requirements](#requirements)
- [Installation](#installation)
- [Getting Started](#getting-started)
  - [Useful Commands](#useful-commands)
- [Appendix](#appendix)

## Information

Cardano Ignite is a toolbox for rapidly deploying and managing Cardano testnets with multiple stake-pools distributed across different simulated regions. It comes with helper tools, such as cardano-db-sync, Blockfrost, Prometheus and Loki. The testnet topology, log files and cardano-node metrics are visualized in built-in Grafana dashboards.

### Showcase

|Status|Block Chain|
|---   |---        |
|<img src=https://github.com/user-attachments/assets/eb089b2b-a8a5-43fa-b330-7a779f4893be width="420" title="Status">|<img src=https://github.com/user-attachments/assets/86d6a91b-1d95-4954-b991-0e46cf0c8047 width="420" title="Block Chain">|

|Physical Topology|Localroot Topology|
|---              |---               |
|<img src=https://github.com/user-attachments/assets/4851a804-9845-448c-9bcd-01cd6bc5753f width="420" title="Physical Topology">|<img src=https://github.com/user-attachments/assets/a536ef03-1dad-4e3c-9557-0729992fb60a width="420" title="Localroot Topology">|

|Network|Process|
|---    |---    |
|<img src=https://github.com/user-attachments/assets/c351d8ec-453a-4b6a-9dd7-ec7c549d67b5 width="420" title="Network">|<img src=https://github.com/user-attachments/assets/0eafeb25-6a6f-4f0b-9aa8-a72e19519db1 width="420" title="Process">|

### Target Audience

This project is designed for developers and end users who wish to run their own Cardano testnet for rapid development or experimentation. It is not intended for performance benchmarking or integration testing, such as the [Antithesis](https://github.com/cardano-foundation/antithesis) project.

### Tech Stack

The following list provides an overview of the key tools and technologies used in the Cardano Ignite project.

|Name                 |Description                                                          |Link                                                 |
|---                  |---                                                                  |---                                                  |
|Blackbox Exporter    |A Prometheus Exporter for probing endpoints over multiple protocols. |https://github.com/prometheus/blackbox_exporter      |
|Blockfrost           |A blockchain explorer and API for Cardano.                           |https://github.com/blockfrost/blockfrost-backend-ryo |
|Cardano CLI          |A command-line interface for the Cardano blockchain.                 |https://github.com/IntersectMBO/cardano-cli          |
|Cardano DB Sync      |A database synchronization tool for the Cardano ledger.              |https://github.com/IntersectMBO/cardano-db-sync      |
|Cardano Node         |A node implementation of the Cardano blockchain.                     |https://github.com/IntersectMBO/cardano-node         |
|Cardano TX Generator |A tool for generating transactions on the Cardano blockchain.        |https://github.com/IntersectMBO/cardano-node/tree/master/bench/tx-generator |
|CoreDNS              |A flexible, extensible DNS server.                                   |https://github.com/coredns/coredns                   |
|Grafana              |A open and composable observability and data visualization platform. |https://github.com/grafana/grafana                   |
|Loki                 |A log aggregation system designed to store and query logs.           |https://github.com/grafana/loki                      |
|PostgreSQL           |An object-relational database system.                                |https://www.postgresql.org                           |
|Prometheus           |A systems and service monitoring system.                             |https://github.com/prometheus/prometheus             |
|Yaci Store           |A modular, high-performance Cardano blockchain indexer and datastore.|https://github.com/bloxbean/yaci-store               |

## Requirements

Cardano Ignite builds on top of Docker Compose. Due to dependencies related to networking, its current compatibility is limited to Linux-based operating systems.

The following applications are required:
- [Docker](https://www.docker.com)
- [Docker Compose](https://github.com/docker/compose)
- [Docker Plugin Loki](https://grafana.com/docs/loki/latest/send-data/docker-driver)
- [Git](https://git-scm.com)
- [Make](https://www.gnu.org/software/make)
- [yq](https://github.com/kislyuk/yq)

## Installation

Please consult the [SETUP.md](./SETUP.md) file for detailed installation instructions.

## Getting Started

- Pull the Cardano Ignite Git repository

  ```
  git clone https://github.com/cardano-foundation/cardano-ignite.git
  cd ./cardano-ignite/
  ```

- List all pre-defined testnets

  ```
  ls -l ./testnets/
  ```

- Build the `global_network` testnet

  ```
  make build testnet=global_network
  ```

- Start the `global_network` testnet **without** optional containers

  ```
  make up testnet=global_network
  ```

- Start the `global_network` testnet **with** optional containers (Blockfrost, TX Generator...)

  ```
  make up-all testnet=global_network
  ```

- Open your browser and navigate to \
  http://localhost:3000

- Enter the credentials below

  ```
  Username:
  cardano

  Password:
  cardano
  ```

- Stop the `global_network` testnet

  ```
  make down testnet=global_network
  ```

### Useful Commands

- Show available commands

  ```
  make help
  ```

- Check for consensus among all pools

  ```
  make validate
  ```

- Show latest block and slot from cardano-db-sync

  ```
  make dbsync
  ```

- Show latest information about the latest block from Blockfrost

  ```
  make block
  ```

- Show detail about all stake-pools from Blockfrost

  ```
  make pools
  ```

## Appendix

- [testnet-generation-tool](https://github.com/cardano-foundation/testnet-generation-tool)
