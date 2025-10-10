#!/usr/bin/env bash

# This script parses the testnet's dockercompose file in order to construct
# a physical topology of the network. This topology is stored in a .sql file
# for later inclusion by the sidecar container.
#
# The end result will be visualized in Topology view in the inclded grafana
# dashboard.

# Check if at least one argument is provided
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <docker-compose-file>" >&2
    exit 1
fi

# Input Docker Compose file (first argument)
YAML_FILE="$1"

# Verify file exists
if [[ ! -f "$YAML_FILE" ]]; then
    echo "Error: File '$YAML_FILE' not found!" >&2
    exit 1
fi

declare -A NETWORKS_UNIQUE

# Start SQL output
cat << 'SQL'
CREATE TABLE ci_nodes (
  id TEXT PRIMARY KEY,
  title TEXT,
  subtitle TEXT,
  mainstat NUMERIC,
  secondarystat NUMERIC,
  color TEXT,
  icon TEXT
);

CREATE TABLE ci_edges (
  id TEXT PRIMARY KEY,
  source TEXT,
  target TEXT
);
SQL

# Extract services using optimized yq call
SERVICES=$(yqg eval '.services | keys | .[]' "$YAML_FILE" 2>/dev/null)

# Process each service
while IFS= read -r SERVICE; do
    # Extract all required fields in one yq call
    CONTAINER_NAME=$(yqg '.services.'"$SERVICE"'.container_name // "XXX"' "$YAML_FILE")
    HOSTNAME=$(yqg '.services.'"$SERVICE"'.hostname // "XXX"' "$YAML_FILE")
    TYPE=$(yqg '.services.'"$SERVICE"'.environment.TYPE // "XXX"' "$YAML_FILE")
    NETWORKS=$(yqg '.services.'"$SERVICE"'.networks' "$YAML_FILE" | yqg 'keys | join(",")' -)
    if [ -z "$NETWORKS" ]; then
        NETWORKS="net"
    fi

    #echo -e "$CONTAINER_NAME\t$HOSTNAME\t$TYPE\t$NETWORKS"

    case "$CONTAINER_NAME" in
        *gw)
            ICON="expand-arrows"
            COLOR="#00FFFF"
            ;;
        synth)
            continue
            ;;
        grafana)
            ICON="monitor"
            COLOR="#FF6B4A"
            ;;
        blackbox)
            ICON="monitor"
            COLOR="#FF6B4A"
            ;;
        db)
            ICON="database"
            COLOR="#FF6B4A"
            ;;
        loki | otlp | jaeger)
            ICON="monitor"
            COLOR="#FF6B4A"
            ;;
        ns)
            ICON="folder"
            COLOR="#FF6B4A"
            ;;
        prometheus)
            ICON="gf-prometheus"
            COLOR="#FF6B4A"
            ;;
        dbsync)
            ICON="database"
            COLOR="#FF6B4A"
            ;;
        yaci)
            ICON="database"
            COLOR="#FF6B4A"
            ;;
        blockfrost)
            ICON="database"
            COLOR="#FF6B4A"
            ;;
        sidecar)
            ICON="monitor"
            COLOR="#FF6B4A"
            ;;
        *)
            ICON=""
            case "$TYPE" in
                *bp*)
                    COLOR="#007FFF"
                    ;;
                relay)
                    COLOR="#FEFE33"
                    ;;
                client)
                    COLOR="#FEFE33"
                    ;;
                privaterelay)
                    COLOR="#D6009A"
                    ;;
                *)
                    COLOR="#FEFE33"
                    ;;
            esac
            ;;
    esac

    # Process networks
    IFS=',' read -ra NETWORK_LIST <<< "$NETWORKS"
    num_elements=${#NETWORK_LIST[@]}

    # Overwrite networks for services that are connected to all networks due to routing.
    case "$CONTAINER_NAME" in
	    "") continue ;;
        ns | prometheus | db | blackbox | yaci | otlp)
            if [[ $num_elements -gt 1 ]]; then
		        NETWORKS="mgmt_net" ;
                IFS=',' read -ra NETWORK_LIST <<< "$NETWORKS"
            fi
            ;;
    esac

    for NETWORK in "${NETWORK_LIST[@]}"; do
        # Skip empty networks
        [[ -z "$NETWORK" ]] && continue

        # Add to unique networks list
        NETWORKS_UNIQUE["$NETWORK"]=1

        # Generate edge IDs
        EDGE_ID_FORWARD="${CONTAINER_NAME}_${NETWORK}"
        EDGE_ID_REVERSE="network_${NETWORK}_${CONTAINER_NAME}"

        # Insert edge records
        cat << SQL_EDGE
INSERT INTO ci_edges (id, source, target) VALUES ('$EDGE_ID_FORWARD', '$CONTAINER_NAME', 'network_$NETWORK');
INSERT INTO ci_edges (id, source, target) VALUES ('$EDGE_ID_REVERSE', 'network_$NETWORK', '$CONTAINER_NAME');
SQL_EDGE
    done

    # Insert service node
    cat << SQL_NODE
INSERT INTO ci_nodes (id, title, subtitle, color, icon) VALUES ('$CONTAINER_NAME', '$CONTAINER_NAME', '$HOSTNAME', '$COLOR', '$ICON');
SQL_NODE

done <<< "$SERVICES"

# Insert network nodes after all services are processed
for NETWORK in "${!NETWORKS_UNIQUE[@]}"; do
    cat << SQL_NETWORK
INSERT INTO ci_nodes (id, title, subtitle, color, icon) VALUES ('network_$NETWORK', '$NETWORK', 'Network', '#00FFAD', 'cloud');
SQL_NETWORK
done
