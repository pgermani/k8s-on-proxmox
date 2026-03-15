# Load Balancer Setup

The load balancer runs as a dedicated virtual machine inside **Proxmox VE** and hosts two services:

- **NGINX** acting as a Layer 4 TCP load balancer for the Kubernetes API and ingress traffic
- **Pi-hole** providing DNS filtering and internal DNS resolution for the local network

Both services run as Docker containers managed with **Docker Compose**.

# Architecture Overview


The load balancer is the **only VM exposed to the internet** for the Kubernetes cluster.

### Kubernetes Traffic

NGINX operates in **TCP stream mode** and forwards incoming traffic to the Kubernetes nodes.

Two types of traffic are handled:

| Port   | Purpose |
|--------|---------|
| `6443` | Kubernetes API server |
| `443`  | Ingress traffic for applications running in the cluster |

External traffic flow:
```
Client -> Router (port forward) -> Load Balancer (NGINX) -> Kubernetes Nodes
```

### DNS Services

Pi-hole provides:

- DNS filtering for the internal network
- local DNS resolution for internal services
- centralized DNS management

# Prerequisites

The load balancer VM requires:

- **Docker Engine**
- **Docker Compose plugin**

Install Docker following the official guide:

https://docs.docker.com/engine/install/ubuntu/#install-using-the-repository

Docker Compose is included as a plugin with Docker installation

# Deploying the NGINX Load Balancer

NGINX is used as a **Layer 4 TCP load balancer** using the `stream` module.

Configuration files:

- Docker Compose file: [nginx/docker-compose.yaml](nginx/docker-compose.yaml)
- NGINX configuration: [nginx/conf/nginx.conf](nginx/conf/nginx.conf)

Before starting the container, adjust the backend node IP addresses inside `nginx.conf`

Start the service:

```
docker compose -f nginx/docker-compose.yaml up -d
```

Verify the container is running, with `docker ps`

# Deploying Pi-hole

Pi-hole is deployed as a container to provide DNS services to the local network.

Configuration files:

- Docker Compose file: [pihole/docker-compose.yaml](pihole/docker-compose.yaml)
- Environment configuration: [pihole/.env.example](pihole/.env.example)

The container runs on a **macvlan network** so it can receive its own IP address on the LAN.

Before starting the container, copy and update env file:

```
cp pihole/.env.example pihole/.env
```

Update the following values:

- timezone
- password
- network configuration


Start the service:

```
docker compose -f pihole/docker-compose.yaml up -d
```

Access the Pi-hole dashboard:

```
http://<PIHOLE-IP>/admin
```