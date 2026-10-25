# Load Balancer Setup

The load balancer runs as a dedicated virtual machine inside **Proxmox VE** and hosts two services:

- **NGINX** acting as a Layer 4 TCP load balancer for the Kubernetes API and ingress traffic
- **Pi-hole** providing DNS filtering and internal DNS resolution for the local network

Both services run as Docker containers managed with **Docker Compose**.

# Architecture Overview


The load balancer is the **only VM exposed to the internet** for the Kubernetes cluster.

### Kubernetes Traffic

NGINX operates in **TCP stream mode** and forwards incoming traffic to the Kubernetes nodes. Ingress is split into an internal and a public plane, each with its own listener - see [ingress-planes.md](k8s/core/ingress-planes.md).

| Port   | Purpose | Reachable from | Forwarded to |
|--------|---------|----------------|--------------|
| `443`  | Internal ingress plane | LAN, VPN | Traefik `websecure` (nodes `443`) |
| `8443` | Public ingress plane, public hostnames only | Internet (router port forward) | Traefik `websecure-ext` (nodes `8444`) |
| `6443` | Kubernetes API server | LAN, VPN | Control plane `6443` |

Both ingress listeners send a PROXY protocol header so Traefik sees the real client IP. TLS is never terminated on the load balancer.

External traffic flow:
```
Client -> Router (port forward 443 -> 8443) -> Load Balancer (NGINX :8443) -> Kubernetes Nodes (:8444)
```

Internal traffic flow:
```
Client -> Pi-hole (internal name -> load balancer) -> Load Balancer (NGINX :443) -> Kubernetes Nodes (:443)
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

- Docker Compose file: [infra/load-balancer/nginx/docker-compose.yaml](../infra/load-balancer/nginx/docker-compose.yaml)
- NGINX configuration: [infra/load-balancer/nginx/conf/nginx.conf](../infra/load-balancer/nginx/conf/nginx.conf)

Before starting the container, replace every `<...>` placeholder inside `nginx.conf`: node IP addresses, home network CIDR, router address and public domain.

The container uses `network_mode: host` instead of published ports. Docker's port publishing NAT can replace the client source address, while the access rules and the PROXY protocol header in `nginx.conf` depend on nginx seeing the real one.

Configure the router to forward external TCP `443` to port `8443` of this VM - never to `443`, which is the internal listener.

Start the service:

```
docker compose -f nginx/docker-compose.yaml up -d
```

Verify the container is running, with `docker ps`

# Deploying Pi-hole

Pi-hole is deployed as a container to provide DNS services to the local network.

Configuration files:

- Docker Compose file: [infra/load-balancer/pihole/docker-compose.yaml](../infra/load-balancer/pihole/docker-compose.yaml)
- Environment configuration: [infra/load-balancer/pihole/.env.example](../infra/load-balancer/pihole/.env.example)

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