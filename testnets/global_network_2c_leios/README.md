# Description

Leios A/B benchmarking testnet: the `global_network_2c` topology (4 pools with
bp + 2 public relays + 1 private relay each, split across NA / EU with regional
gateways) where **every** node runs the Leios (Dijkstra-era) cardano-node.
Pools p1*/p2* form variant A and p3*/p4* variant B, so tx-submission logic
versions or node source refs can be compared within a single run. Tx load is
driven by the legacy **tx-generator** into each pool's private relay.

All components track the revisions pinned by the `prototype-2026w32` tag of
[ouroboros-leios](https://github.com/input-output-hk/ouroboros-leios).

## Cardano-Node

- **Version**: 11.1.0.164 (Leios)
- **Branch**: leios-prototype (c5f7d9121)
- **Binary/Source**: Source

## Cardano-CLI

- **Branch**: leios-prototype (de7865577)
- **Binary/Source**: Source

## Cardano-DB-Sync

- **Branch**: jl/leios-prototype (6d7f61347)
- **Binary/Source**: Source

## A/B knobs

- `TX_SUBMISSION_LOGIC_VERSION_A` / `_B`: tx-submission logic per variant
  (defaults: A=1, B=2)
- `CARDANO_NODE_REF_A` / `_B` and `CARDANO_NODE_IMAGE_TAG_A` / `_B`: compare
  source refs (defaults: both at the stock leios-prototype rev)
- `POOL_PAIR_A_CPUSET` / `POOL_PAIR_B_CPUSET` / `MGMT_CPUSET`: CPU pinning
  (defaults: 2-4 / 5-7 / 0-1); at the default TPS=50 consider wider sets
- `TPS`: tx-generator rate (default 50)

## Usage

    make build testnet=global_network_2c_leios
    make up-all testnet=global_network_2c_leios

Example A/B of a patched node as variant B:

    CARDANO_NODE_REF_B=my-leios-branch CARDANO_NODE_IMAGE_TAG_B=my_leios_b \
      make build testnet=global_network_2c_leios

## Notes

- Genesis is generated with the Leios cardano-cli (testnet-generation-tool
  `karknu/leios`) so every pool gets a BLS voting key registered as leiosKey;
  without it pools silently never certify EBs.
- The db-synthesizer is not Leios/Dijkstra-aware: `PRE_EPOCHS` is hardcoded
  to 0 and the network always starts from genesis.
- The legacy tx-generator resolves `targetNodes.addr` as literal IPv4, so
  `TX_GENERATOR_TARGETS` must stay static IPs (the four private relays).
