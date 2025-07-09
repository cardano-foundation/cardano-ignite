# Setup

## Index

- [Installation](#installation)
  - [Prerequisites](#prerequisites)
  - [Docker](#docker)

## Installation

### Prerequisites

Please install the dependencies below. All commands are compatible with Debian 12.

- Install `git`, `make` and `yq` with your package manager

  ```
  sudo apt update
  sudo apt install --no-install-recommends -y git make yq
  ```

> [!NOTE]
> If `yq` isn’t available in your package manager, you can download the binary from GitHub and manually copy it to `/usr/local/bin/yq`.

### Docker

- Install Docker Engine according to \
  https://docs.docker.com/engine/install

> [!NOTE]
> The Docker website maintains installation guides for multiple distributions.

- Install `ca-certificates` and `curl` with your package manager

  ```
  sudo apt update
  sudo apt install --no-install-recommends -y ca-certificates curl
  ```

- Create APT keyrings directory

  ```
  sudo install --directory --owner=root --group=root --mode=0755 /etc/apt/keyrings
  ```

- Download Docker GPG public key

  ```
  sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
  ```

- Ensure the Docker GPG public key is readable

  ```
  sudo chmod a+r /etc/apt/keyrings/docker.asc
  ```

- Add the Docker APT repository

  ```
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "${VERSION_CODENAME}") stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  ```

- Refresh the APT package cache

  ```
  sudo apt update
  ```

- Install Docker Engine

  ```
  sudo apt install --no-install-recommends -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  ```

- Install Docker Plugin to stream logs to Loki

  ```
  sudo docker plugin install grafana/loki-docker-driver --alias loki --grant-all-permissions
  ```

- Add your user to the docker group

  ```
  sudo usermod -aG docker $USER
  ```

  Relog to have the group change take affect.

### Dummy Interface

The Docker setup for advanced test networks uses a macvlan driver in bridge mode, requiring assignment of a parent network interface. You can explicitly specify this parent interface using the `HOST_INTERFACE` environment variable. When unset, the Makefile automatically selects an available interface, prioritizing dummy interfaces over physical ones.

The primary advantage of selecting a dummy interface is network isolation: Unlike physical interfaces (e.g., eth0), a dummy device:
* Prevents MAC address leakage
* Avoids potential conflicts with other devices on your LAN.

This isolation ensures test network activities don't inadvertently impact or become visible to external networks.

To create a dummy device run the following commands:

  ```
  sudo modprobe dummy
  sudo ip link add dummy0 type dummy
  sudo ip link set dummy0 up
  ```

Check your linux dist for instructions on how to have the dummy device be created at boot.
