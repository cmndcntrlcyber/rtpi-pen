# RTPI-Pen

A Pentest flavor for the Red Team Portable Infrastructure 

RTPI-Pen is a comprehensive penetration testing environment that combines multiple security and reporting tools in a containerized setup.

## Overview

This project provides a complete penetration testing infrastructure with the following main components:

- **Kasm Workspaces**: Browser-based containerized desktop environments
- **Sysreptor**: Penetration testing report generator
- **Empire**: PowerShell post-exploitation framework
- **Portainer**: Docker container management UI
- **Support services**: PostgreSQL, Redis, Nginx, Caddy

## Prerequisites

- Docker Engine 20.10+
- Docker Compose 2.0+
- At least 16GB RAM
- At least 50GB disk space

## Getting Started

### Installation

1. Clone this repository:
   ```bash
   git clone https://your-repo-url/rtpi-pen.git
   cd rtpi-pen
   ```

2. Configure environment variables:
   ```bash
   cp .env.example .env
   # Edit .env with your preferred settings
   ```

3. Start the environment:
   ```bash
   ./scripts/startup.sh
   ```

### Access Services

Once the environment is running, you can access the following services:

- **Kasm Workspaces**: https://localhost:443
- **Sysreptor**: http://localhost:9000
- **Portainer**: https://localhost:9443
- **Empire**: http://localhost:1337

## Network Structure

The environment consists of three main networks:

1. **Bridge Network (172.17.0.0/16)**: Default Docker bridge network
2. **Kasm Network (172.18.0.0/16)**: Network for Kasm workspace containers
3. **Sysreptor Network (172.20.0.0/16)**: Network for Sysreptor services

## Data Persistence

All data is stored in Docker volumes for persistence. Backups can be created using:

```bash
./scripts/backup.sh
```

## Management Scripts

The `scripts/` directory contains several helper scripts:

- `startup.sh`: Start all services in the correct order
- `shutdown.sh`: Gracefully stop all services
- `backup.sh`: Create backups of all data
- `restore.sh`: Restore data from backups
- `health-check.sh`: Check the health of all services
- `cleanup.sh`: Clean up unused images and volumes

## Security Considerations

This environment contains security testing tools. Please ensure:

1. This environment is deployed in a secure network
2. Default passwords are changed in the `.env` file
3. Proper access controls are implemented

## License

[Your License Information]

## Contributing

[Your Contribution Guidelines]
