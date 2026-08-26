# Description

Static-topology variant of `global_network_2c`. Same four pools, two continents
and A/B split, but every connection is pinned: peer sharing is off
(`PeerSharing: false`), ledger peers are off (`useLedgerAfterSlot: -1`) and no
public roots are configured, so a node only ever talks to the peers listed in
its local roots.

A/B and management use separate CPU sets in order to isolate their impact on
each other. This testnet requires at least 8 cores to run.

Edit cardano_node_variant_a, cardano_node_variant_b, node_env_variant_a, and
node_env_variant_b to match the test.

# Topology

Pools p1 and p3 are in NA, p2 and p4 are in EU. p1/p2 are variant A, p3/p4 are
variant B.

| Node          | Local roots                                                    |
|---            |---                                                             |
| pXbp          | pXr1, pXr2, pXr3                                               |
| pXr1, pXr2    | pXbp, the sibling relay, plus the inter-pool edges below       |
| pXr3          | pXbp (private relay, no inter-pool edges)                      |
| c1 .. c6      | two ring neighbours, plus one relay per pool                   |

Private relays take client connections but no inter-pool edges, so they are a
low-fan-in node carrying the same class of work as a public relay.

Relay N of a pool connects to both relays of the other pool on its own
continent, and to relay N of every pool on the other continent:

```
p1r1: p3r1 p3r2 | p2r1 p4r1        p3r1: p1r1 p1r2 | p2r1 p4r1
p1r2: p3r1 p3r2 | p2r2 p4r2        p3r2: p1r1 p1r2 | p2r2 p4r2
p2r1: p4r1 p4r2 | p1r1 p3r1        p4r1: p2r1 p2r2 | p1r1 p3r1
p2r2: p4r1 p4r2 | p1r2 p3r2        p4r2: p2r1 p2r2 | p1r2 p3r2
```

Every edge is declared on both endpoints so either side can re-establish it
after a restart.

Clients keep the c1-c2-...-c6-c1 ring and add one relay per pool, spread over
all three relays so each carries two clients, one from each continent:

```
c1 (EU), c6 (NA) -> p1r1 p2r1 p3r1 p4r1
c2 (NA), c3 (EU) -> p1r2 p2r2 p3r2 p4r2
c4 (EU), c5 (NA) -> p1r3 p2r3 p3r3 p4r3
```

The tx-generator (c2) submits to c1 .. c6 rather than to relays, so every
transaction enters the network through a client and reaches a pool over that
client's single relay for the pool.

# Implementation

The intra-pool local roots come from `cardano-node/cmd.sh` with
`NO_INTERPOOL_LOCALROOTS=true`, which reduces a relay to its own bp and its
sibling relay. Everything else is listed per service in `EXTRA_LOCALROOTS`, so
the whole graph is visible in `docker-compose.yaml`.

`USE_LEDGER_AFTER_SLOT=-1` and `PEER_SHARING=false` are literals in
`x-node-env-common` rather than passthroughs; overriding them from the
environment would defeat the point of the testnet.

The peer selection targets in `testnet.yaml` are raised to 8 so they do not cap
the six local roots a relay or client has, and the big ledger peer targets are 0.
