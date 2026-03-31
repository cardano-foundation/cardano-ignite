# Description

Reduced two-continent variant of `global_network` for A/B benchmarking.
Optional services like blockfrost and yaci are not included.

The A and B set each run one pool in NA and one pool in EU, along with public and private relays.

A/B and management use separate CPU sets in order to isolate their impact on each other.
This testnet requires at least 8 cores to run.

Edit cardano_node_variant_a, cardano_node_variant_b, node_env_variant_a, and
node_env_variant_b to match the test.
