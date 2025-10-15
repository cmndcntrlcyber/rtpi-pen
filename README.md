# RTPI-PEN: Red Team Penetration Infrastructure

A comprehensive penetration testing platform providing security professionals with a complete toolkit for Red Team operations, C2 frameworks, security assessments, and automated SSL certificate management.
![](https://c3s-consulting.notion.site/image/https%3A%2F%2Fprod-files-secure.s3.us-west-2.amazonaws.com%2Fb14dfce6-e02e-43c5-b633-a26dc582c1f6%2F11f9080f-b8d4-48df-8a16-767ef006b428%2FRTPI-NO-BG.png?id=92e087b7-2d26-4559-aee1-1a8442229383&table=block&spaceId=b14dfce6-e02e-43c5-b633-a26dc582c1f6&width=250&userId=&cache=v2)
## 🎯 What's Included

### Core Infrastructure Services
- **🏥 Self-Healing Service** - Automated monitoring, repair, and recovery system
- **🗄️ Database Service** - PostgreSQL with multiple databases (rtpi_main, kasm, sysreptor)
- **⚡ Cache Service** - Redis cluster with multiple instances for different services
- **🐳 Orchestrator Service** - Portainer for container management
- **🌐 Proxy Service** - Nginx reverse proxy with SSL termination
- **🔧 Tools Service** - Containerized security tools

### Application Services
- **🖥️ Kasm Workspaces** - Browser-based virtual desktops (installed natively)
- **📊 SysReptor** - Penetration testing documentation and reporting
- **👑 PowerShell Empire** - Command & Control framework (installed natively)
- **📦 Docker Registry** - Local container image registry
- **🌐 Node.js Service** - Additional development/API service

### Pre-installed Security Tools
- **Network Analysis**: Nmap, Wireshark, net-tools
- **Exploitation**: Metasploit, exploitdb, python3-impacket
- **Password Attacks**: Hashcat, Hydra, CrackMapExec
- **Active Directory**: Bloodhound, CrackMapExec, Impacket
- **Web Tools**: Proxychains, curl, wget
- **Development**: PowerShell, Python3, Java, Go, Node.js
- **Windows Tools**: Wine, mingw-w64, PowerSploit
- **Frameworks**: PowerShell Empire, additional C2 tools

## 🚀 Quick Start

### Prerequisites
- **Operating System**: Ubuntu 20.04+ (tested)
- **Docker**: 20.10+ with Docker Compose v2
- **Access Level**: Root access required (sudo)
- **Minimum**: 8GB RAM, 4 CPU cores, 20GB disk space
- **Recommended**: 16GB+ RAM, 8+ CPU cores, 40GB+ disk space

### Deployment Methods

## 🏗️ Method 1: Fresh Installation (Recommended)

The fresh installation method provides a complete setup with native Kasm Workspaces, native Empire C2, and containerized supporting services.

### Features:
- **Native Kasm Installation**: Installs Kasm Workspaces 1.17.0 directly on the host
- **Native Empire C2**: Installs PowerShell Empire natively for better performance
- **Containerized Services**: Supporting services run in Docker containers
- **Automated Setup**: Complete system configuration and package installation
- **Self-Healing**: Includes monitoring and repair capabilities

### Usage:
```bash
# Clone the repository
git clone https://github.com/attck-nexus/rtpi-pen.git
cd rtpi-pen

# Make the script executable
chmod +x fresh-rtpi-pen.sh

# Run the complete installation (requires root)
sudo ./fresh-rtpi-pen.sh

# After installation, start containerized services
docker compose up -d
```

## 🔒 Method 2: Advanced Build with SSL (Production)

The advanced build method includes SSL certificate automation with Let's Encrypt and Cloudflare DNS.

### Features:
- **SSL Certificate Automation**: Automatic Let's Encrypt certificate generation
- **Cloudflare DNS Management**: Automated DNS record creation
- **Production Ready**: Secure configuration for production environments
- **Custom Domain Support**: Support for custom organizational domains

### Usage:
```bash
# Make the script executable
chmod +x build.sh

# Deploy with SSL certificates for organization "myorg"
sudo ./build.sh --slug myorg --enable-ssl

# Deploy with custom server IP
sudo ./build.sh --slug myorg --enable-ssl --server-ip 192.168.1.100

# Standard deployment (no SSL)
sudo ./build.sh
```

**Generated SSL-enabled domains (example with slug 'myorg'):**
- `myorg.attck-node.net` - Main dashboard
- `myorg-reports.attck-node.net` - SysReptor 
- `myorg-empire.attck-node.net` - Empire C2
- `myorg-mgmt.attck-node.net` - Portainer
- `myorg-kasm.attck-node.net` - Kasm Workspaces

For detailed SSL configuration, see [SSL_AUTOMATION_README.md](SSL_AUTOMATION_README.md).

## 🌐 Service Access

### Standard Access (Fresh Installation)

| Service | Primary URL | Direct URL | Description |
|---------|-------------|------------|-------------|
| **Kasm Workspaces** | - | https://localhost:8443 | Virtual desktop environment |
| **Empire C2** | - | http://localhost:1337 | Command & Control framework |
| **Portainer** | - | https://localhost:9443 | Container management |
| **SysReptor** | - | http://localhost:7777 | Reporting platform |
| **Self-Healing API** | - | http://localhost:8888/health | Health monitoring |
| **Docker Registry** | - | http://localhost:5001 | Local container registry |

### SSL-Enabled Access (Advanced Build)

| Service | SSL URL | Description |
|---------|---------|-------------|
| **Main Dashboard** | https://[slug].attck-node.net | Unified portal |
| **SysReptor** | https://[slug]-reports.attck-node.net | Reporting platform |
| **Empire C2** | https://[slug]-empire.attck-node.net | Command & Control |
| **Portainer** | https://[slug]-mgmt.attck-node.net | Container management |
| **Kasm Workspaces** | https://[slug]-kasm.attck-node.net | Virtual desktops |

## 🌐 Custom Hostnames (Optional)

RTPI-PEN includes a hosts configuration script that provides clean, memorable URLs for all services.

### Configure Custom Hostnames
```bash
# Add custom hostnames to /etc/hosts
sudo ./setup/configure-hosts.sh add

# Remove custom hostnames
sudo ./setup/configure-hosts.sh remove

# Verify hostname resolution
./setup/configure-hosts.sh verify

# Show current RTPI-PEN entries
./setup/configure-hosts.sh show

# Backup current hosts file
sudo ./setup/configure-hosts.sh backup

# Restore from backup
sudo ./setup/configure-hosts.sh restore
```

### Service Access with Custom Hostnames
| Service | Custom URL | Standard URL |
|---------|------------|--------------|
| **Kasm Workspaces** | https://kasm.rtpi.local:8443 | https://localhost:8443 |
| **Empire C2** | http://empire.rtpi.local:1337 | http://localhost:1337 |
| **Portainer** | https://portainer.rtpi.local:9443 | https://localhost:9443 |
| **SysReptor** | http://sysreptor.rtpi.local:7777 | http://localhost:7777 |
| **Self-Healing API** | http://healer.rtpi.local:8888 | http://localhost:8888 |
| **Docker Registry** | http://registry.rtpi.local:5001 | http://localhost:5001 |

### Additional Hostnames
The script also configures shorter alternative names:
- `kasm.local`, `empire.local`, `portainer.local`, `sysreptor.local`
- `admin.rtpi.local`, `dashboard.rtpi.local`, `tools.rtpi.local`

## 🔧 Management & Operations

### System Management
```bash
# Check system status
systemctl status kasm empire

# View service logs
journalctl -u kasm -f
journalctl -u empire -f

# Start/stop native services
sudo systemctl start kasm empire
sudo systemctl stop kasm empire

# Restart native services
sudo systemctl restart kasm empire
```

### Container Management
```bash
# View container status
docker compose ps

# View all logs
docker compose logs -f

# View specific service logs
docker compose logs -f rtpi-healer

# Restart specific service
docker compose restart rtpi-proxy

# Stop all containers
docker compose down

# Start all containers
docker compose up -d
```

### Health Monitoring
```bash
# Check self-healing service
curl http://localhost:8888/health

# Check Empire C2 status
curl http://localhost:1337/api/v2/admin/users

# Check Kasm status
curl -k https://localhost:8443/api/public/get_token

# Check database connectivity
docker compose exec rtpi-database pg_isready -U rtpi
```

## 📁 Data Persistence

### Volume Management
- `rtpi_database_data` - Main PostgreSQL data
- `rtpi_cache_data` - Redis cache data  
- `rtpi_orchestrator_data` - Portainer configuration
- `rtpi_tools_data` - Security tools data
- `rtpi_healer_data` - Self-healing service data
- `sysreptor-app-data` - SysReptor application data
- `sysreptor-caddy-data` - Caddy proxy data
- `empire_data` - Empire C2 framework data (if containerized)
- `registry_data` - Local Docker registry data

### Native Service Data
- **Kasm Workspaces**: `/opt/kasm/current/`
- **Empire C2**: `/opt/Empire/`
- **SSL Certificates**: `/opt/rtpi-pen/certs/`

### Backup Strategy
```bash
# Backup container volumes
docker run --rm -v rtpi_database_data:/data -v $(pwd):/backup alpine tar czf /backup/database-backup.tar.gz -C /data .

# Backup native services
sudo tar czf kasm-backup.tar.gz -C /opt/kasm/current .
sudo tar czf empire-backup.tar.gz -C /opt/Empire .

# Backup SSL certificates (if using advanced build)
sudo tar czf certs-backup.tar.gz -C /opt/rtpi-pen/certs .
```

## 🔐 Default Credentials

### Native Services
- **Kasm Workspaces**: `admin@kasm.local` / `password` (change on first login)
- **Empire C2**: `empireadmin` / `password123` (check `/opt/Empire/empire/server/config.yaml`)

### Containerized Services
- **Portainer**: `admin` / `admin` (set on first access)
- **SysReptor**: No default credentials (set during first setup)

### Database Configuration
- **Main Database**: `rtpi` / `rtpi_secure_password`
- **SysReptor Database**: `sysreptor` / `sysreptorpassword`
- **Redis Cache**: `rtpi_redis_password`

## 🛠️ Development & Customization

### Adding Custom Tools
```bash
# Access tools container
docker compose exec rtpi-tools /bin/bash

# Install additional tools
apt update && apt install -y your-tool

# Install Python packages
pip3 install your-package

# Access native Empire installation
cd /opt/Empire
./ps-empire client
```

### Modifying Services
```bash
# Edit service configuration
nano services/rtpi-proxy/nginx/conf.d/rtpi-pen.conf

# Rebuild and restart service
docker compose build rtpi-proxy
docker compose restart rtpi-proxy

# Edit native service configurations
sudo nano /opt/kasm/current/conf/app/kasmweb.yaml
sudo nano /opt/Empire/empire/server/config.yaml
```

## 🔍 Troubleshooting

### Installation Issues
```bash
# Check installation logs
tail -f /var/log/syslog | grep -E "(kasm|empire)"

# Verify native services
systemctl status kasm empire

# Check container status
docker compose ps

# Check for port conflicts
sudo netstat -tlnp | grep -E "(80|443|1337|8443|9443)"
```

### Service Not Starting
```bash
# Check specific service logs
journalctl -u empire -f
journalctl -u kasm -f

# Check container logs
docker compose logs rtpi-healer

# Check file permissions
ls -la /opt/Empire/ps-empire
ls -la /opt/kasm/current/
```

### Network Issues
```bash
# Check Docker networks
docker network ls

# Test connectivity
docker compose exec rtpi-proxy ping rtpi-database

# Check firewall rules
sudo ufw status
```

### Database Issues
```bash
# Check database connectivity
docker compose exec rtpi-database pg_isready -U rtpi

# Connect to database
docker compose exec rtpi-database psql -U rtpi -d rtpi_main

# Check database logs
docker compose logs rtpi-database
```

## 📊 System Requirements

### Minimum Requirements
- **RAM**: 8GB
- **CPU**: 4 cores
- **Disk**: 20GB free space
- **Network**: Internet connectivity for initial setup

### Recommended Requirements
- **RAM**: 16GB+
- **CPU**: 8+ cores
- **Disk**: 40GB+ free space
- **Network**: Dedicated network segment

### Performance Considerations
- **Native Services**: Kasm and Empire run natively for better performance
- **Containerized Services**: Supporting services run in isolated containers
- **Network**: Internal container networks for security
- **Storage**: Persistent volumes for data retention

## 🔒 Security Considerations

**⚠️ Important Security Warning**

This platform includes penetration testing tools and frameworks designed for authorized security testing only.

### Security Features
- **Network Segmentation**: Services isolated by function
- **SSL Support**: Automated certificate management
- **Access Controls**: Role-based access through services
- **Container Isolation**: Strict isolation between services
- **Native Security**: Critical services run natively for better control

### Security Best Practices
- **Only use in authorized environments**
- **Isolate from production networks**
- **Change default passwords immediately**
- **Keep services updated regularly**
- **Monitor service logs for anomalies**
- **Use proper firewall rules**
- **Implement network segmentation**

## 📋 File Structure

```
rtpi-pen/
├── fresh-rtpi-pen.sh          # Main installation script
├── build.sh                   # Advanced build with SSL
├── docker-compose.yml         # Container orchestration
├── README.md                  # This file
├── SSL_AUTOMATION_README.md   # SSL configuration guide
├── configs/                   # Configuration files
│   ├── rtpi-empire/          # Empire C2 configuration
│   └── rtpi-sysreptor/       # SysReptor configuration
├── services/                  # Container service definitions
│   ├── rtpi-cache/           # Redis cache service
│   ├── rtpi-database/        # PostgreSQL database
│   ├── rtpi-healer/          # Self-healing service
│   ├── rtpi-orchestrator/    # Portainer service
│   ├── rtpi-proxy/           # Nginx reverse proxy
│   ├── rtpi-tools/           # Security tools container
│   └── rtpi-web/             # Web dashboard
├── setup/                    # Setup and maintenance scripts
│   ├── cert_manager.sh       # SSL certificate management
│   ├── cert_renewal.sh       # Certificate renewal
│   └── cloudflare_dns_manager.sh # DNS management
├── legacy/                   # Legacy deployment methods
└── repair-scripts/           # Emergency repair scripts
```

## 🆘 Support & Contributing

### Getting Help
1. Check the troubleshooting section above
2. Review service logs: `journalctl -u [service]` or `docker compose logs [service]`
3. Check system requirements and port conflicts
4. Verify all services are running: `systemctl status kasm empire`

### Contributing
1. Fork the repository
2. Create a feature branch
3. Test your changes thoroughly
4. Submit a pull request with detailed description

### Reporting Issues
When reporting issues, please include:
- Operating system and version
- System specifications (RAM, CPU, disk)
- Installation method used
- Output of `systemctl status kasm empire`
- Output of `docker compose ps`
- Relevant log output

## 📋 License

See the [LICENSE](LICENSE) file for details.

---

**Built for security professionals, by security professionals** 🔴

### Quick Reference Commands

#### Installation:
```bash
sudo ./fresh-rtpi-pen.sh       # Fresh installation
sudo ./build.sh --slug myorg --enable-ssl  # Advanced with SSL
```

#### Management:
```bash
systemctl status kasm empire   # Check native services
docker compose ps              # Check containers
docker compose logs -f         # View all logs
```

#### Monitoring:
```bash
curl http://localhost:8888/health     # Self-healing status
curl -k https://localhost:8443/api/public/get_token  # Kasm status
curl http://localhost:1337/api/v2/admin/users        # Empire status
```

**For detailed configuration and troubleshooting, refer to the sections above.**
