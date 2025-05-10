# RTPI-PEN Container Orchestration

A comprehensive Docker-based platform for Red Team Penetration Infrastructure, combining multiple security-focused services in a container stack.

## Overview

RTPI-PEN provides a pre-configured environment with multiple security tools including:

- Kasm Workspaces (remote browser isolation)
- SysReptor (penetration testing documentation)
- Empire (C2 framework)
- Nginx Proxy Manager
- Local Docker Registry
- Portainer CE

## Architecture

The stack is designed with the following components:

- **Portainer-based Orchestrator**: Central management container that provides a web UI and Docker management
- **Multiple Network Segments**: Isolated network segments for different tool stacks
- **Proxy Integration**: All web UIs configured for access through Kasm proxy

## Getting Started

### Prerequisites

- Docker 20.10+ and Docker Compose v2
- 8GB+ RAM recommended
- 40GB+ free disk space

### Quick Start

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/rtpi-pen.git
   cd rtpi-pen
   ```

2. Build the container:
   ```bash
   docker compose build
   ```

3. Start the services:
   ```bash
   docker compose up -d
   ```

## Available Services

| Service | URL | Default Port | Description |
|---------|-----|--------------|-------------|
| Portainer | https://localhost:9443 | 9443 | Container management UI |
| Kasm Workspaces | https://localhost:8443 | 8443 | Remote browser isolation |
| SysReptor | http://localhost:9000 | 9000 | Penetration testing documentation |
| Empire | http://localhost:1337 | 1337, 5000 | C2 framework |
| Nginx Proxy Manager | http://localhost:81 | 80, 81, 443 | Reverse proxy |
| Local Registry | http://localhost:5000 | 5000 | Docker image registry |

## Service Configuration

### Kasm Workspaces

Kasm provides browser isolation and virtual desktop services. The configuration is located in `/opt/kasm/1.15.0/` and is automatically set up by the container.

### SysReptor

SysReptor is a penetration testing documentation tool. Environment variables can be modified in `configs/rtpi-sysreptor/app.env`.

### Empire

Empire C2 framework is accessible on ports 1337 and 5000. Data is persisted in the `empire_data` volume.

## Building and Publishing

To build and publish the image to Docker Hub:

```bash
# Build the image
docker build -t yourusername/rtpi-pen:latest .

# Push to Docker Hub
docker push yourusername/rtpi-pen:latest
```

## Custom Deployments

You can modify `docker-compose.yml` to adjust service configurations, port mappings, and volume persistence according to your requirements.

## Volumes and Data Persistence

All service data is stored in named Docker volumes:

- `portainer_data`: Portainer configuration and data
- `kasm_db_1.15.0`: Kasm database and settings
- `sysreptor-app-data`: SysReptor application data
- `sysreptor-db-data`: SysReptor database
- `empire_data`: Empire C2 framework data
- `registry_data`: Local Docker registry data

## Troubleshooting

If you encounter issues:

1. Check container logs:
   ```bash
   docker compose logs service-name
   ```

2. Verify all services are running:
   ```bash
   docker compose ps
   ```

3. Restart a specific service:
   ```bash
   docker compose restart service-name
   ```

## License

See the LICENSE file for details.
