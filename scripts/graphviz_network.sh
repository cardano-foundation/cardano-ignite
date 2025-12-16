#!/usr/bin/env bash

get_region() {
    local ip=$1
    # Extract first 3 octets (for /24 network)
    local network_prefix=$(echo "$ip" | cut -d'.' -f1-3)
    
    case "$network_prefix" in
        "172.16.1")
            echo "North America"
            ;;
        "172.16.3")
            echo "Europe"
            ;;
        "172.16.4")
            echo "Asia"
            ;;
        *)
            echo "Unknown"
            ;;
    esac
}

# Step 1: Get all running container IDs
containers=$(docker ps -q)

# Step 2: Map container IDs to names and IPs
declare -A id_to_name ip_to_name ip_to_region name_to_region

for container in $containers; do
    name=$(docker inspect $container --format='{{.Name}}' | sed 's/\///')  # Remove leading slash
    ip=$(docker inspect $container --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' | head -n 1 | tr -d '[:space:]')

    if [[ -n "$name" && -n "$ip" ]]; then
        id_to_name[$container]=$name
        ip_to_name[$ip]=$name
        
        # Get and store region
        region=$(get_region "$ip")
        ip_to_region[$ip]=$region
        name_to_region[$name]=$region
    fi
done

# Step 3: Detect cardano-node and send SIGUSR1 in one loop
declare -A containers_with_node

for container in $containers; do
    if [[ -n "${id_to_name[$container]}" ]]; then
        # Check for cardano-node
        pid=$(docker exec $container ps -eo pid,comm --no-headers 2>/dev/null | grep cardano-node | awk '{print $1}')
        if [[ -n "$pid" ]]; then
            containers_with_node[$container]=1
            docker exec $container kill -SIGUSR1 $pid
        fi
    fi
done

# Step 4: Wait once for logs to update
sleep 2


# Step 5: Collect directed edges from activePeers with color coding
edges=()

for container in "${!containers_with_node[@]}"; do
    own_name=${id_to_name[$container]}

    # Extract JSON data
    raw_data=$(docker logs $container 2>&1 | grep DebugState | tail -n 1)

    # Extract activePeers, localRootPeers, bigLedgerPeers
    active_peers_ips=$(echo "$raw_data" | jq -r 'select(has("data") and .data.kind == "DebugState") | .data.activePeers[].address' 2>/dev/null)
    local_root_ips=$(echo "$raw_data" | jq -r 'select(has("data") and .data.kind == "DebugState") | .data.localRootPeers.groups[][2][][0].address' 2>/dev/null)
    big_ledger_ips=$(echo "$raw_data" | jq -r 'select(has("data") and .data.kind == "DebugState") | .data.publicRootPeers.bigLedgerPeers[].address' 2>/dev/null)

    # Convert peer IP lists to arrays
    local_root_ips_array=()
    while read -r ip; do
        [[ -n "$ip" && "$ip" != "null" ]] && local_root_ips_array+=("$(echo "$ip" | tr -d '[:space:]')")  # Clean IP
    done <<< "$local_root_ips"

    big_ledger_ips_array=()
    while read -r ip; do
        [[ -n "$ip" && "$ip" != "null" ]] && big_ledger_ips_array+=("$(echo "$ip" | tr -d '[:space:]')")  # Clean IP
    done <<< "$big_ledger_ips"

    active_peers_ips_array=()
    while read -r ip; do
        [[ -n "$ip" && "$ip" != "null" ]] && active_peers_ips_array+=("$(echo "$ip" | tr -d '[:space:]')")  # Clean IP
    done <<< "$active_peers_ips"

    # Process each peer IP
    for peer_ip in "${active_peers_ips_array[@]}"; do
        if [[ -n "${ip_to_name[$peer_ip]}" ]]; then
            peer_name=${ip_to_name[$peer_ip]}

            # Determine color
            color="red"
            for root_ip in "${local_root_ips_array[@]}"; do
                if [[ "$root_ip" == "$peer_ip" ]]; then
                    color="black"
                    break
                fi
            done

            if [[ "$color" == "red" ]]; then
                for big_ip in "${big_ledger_ips_array[@]}"; do
                    if [[ "$big_ip" == "$peer_ip" ]]; then
                        color="blue"
                        break
                    fi
                done
            fi

            edges+=("$own_name $peer_name $color")
        fi
    done
done

# Step 6: Separate and sort edges
black_edges=()
blue_edges=()
red_edges=()

for edge in "${edges[@]}"; do
    [[ -z "$edge" ]] && continue
    color=$(echo "$edge" | awk '{print $3}')
    if [[ "$color" == "black" ]]; then
        black_edges+=("$edge")
    elif [[ "$color" == "blue" ]]; then
        blue_edges+=("$edge")
    else
        red_edges+=("$edge")
    fi
done

# Sort each group alphabetically by source name
sort_edges() {
    local edges=("$@")
    if (( ${#edges[@]} > 0 )); then
        IFS=$'\n'
        sorted=($(printf "%s\n" "${edges[@]}" | sort -k1,1))
        unset IFS
        echo "${sorted[@]}"
    else
        echo ""
    fi
}

black_sorted=($(sort_edges "${black_edges[@]}"))
blue_sorted=($(sort_edges "${blue_edges[@]}"))
red_sorted=($(sort_edges "${red_edges[@]}"))

# Step 7: Output DOT format with color-coded edges and region info for nodes
echo "digraph cardano_connections {"
echo "  node [shape=box];"  # Optional: Set a default shape for all nodes

# Collect all unique node names from edges
declare -A node_names
for edge in "${black_edges[@]}" "${blue_edges[@]}" "${red_edges[@]}"; do
    [[ -z "$edge" ]] && continue
    read src dst _ <<< "$edge"
    node_names["$src"]=1
    node_names["$dst"]=1
done

# Define nodes with custom labels
for name in "${!node_names[@]}"; do
    region=${name_to_region[$name]}
    echo "  \"$name\" [label=\"$name\\n($region)\"];"
done

# Output the edges
for edge in "${black_edges[@]}"; do
    [[ -z "$edge" ]] && continue
    read src dst color <<< "$edge"
    echo "  \"$src\" -> \"$dst\" [color=\"$color\"];"
done
for edge in "${blue_edges[@]}"; do
    [[ -z "$edge" ]] && continue
    read src dst color <<< "$edge"
    echo "  \"$src\" -> \"$dst\" [color=\"$color\"];"
done
for edge in "${red_edges[@]}"; do
    [[ -z "$edge" ]] && continue
    read src dst color <<< "$edge"
    echo "  \"$src\" -> \"$dst\" [color=\"$color\"];"
done
echo "}"
