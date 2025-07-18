# RTPI-PEN Docker Container Repair Solution

## Overview

This comprehensive repair solution addresses Docker container restart loops and related issues in the RTPI-PEN (Red Team Penetration Infrastructure) environment. The solution provides automated diagnosis, repair, and validation tools to restore system functionality.

## Problem Summary

The RTPI-PEN system was experiencing multiple Docker containers in restart loops:
- **kasm_agent** (Kasm Workspaces virtual desktop agent)
- **rtpi-healer** (Self-healing monitoring service)
- **ps-empire** (PowerShell Empire C2 framework)
- **rtpi-orchestrator** (Container orchestration service)

### Root Causes Identified

1. **Initialization Order Failure**: Services starting before dependencies are ready
2. **Missing Configuration Files**: Required YAML configs and SSL certificates not present
3. **Permission Issues**: Incorrect file ownership and Docker socket access
4. **Self-Healing Service Down**: The healer service couldn't perform its functions
5. **Dependency Chain Broken**: Services failing cascading failures

## Repair Solution Components

### 1. Main Orchestrator (`rtpi-pen-repair.sh`)

The primary interface for the repair solution with an interactive menu system.

```bash
./repair-scripts/rtpi-pen-repair.sh
```

**Features:**
- System assessment and diagnosis
- Interactive repair menu
- Colored output for better readability
- Automatic backup creation
- Comprehensive error handling
- Success/failure summaries

### 2. Emergency Repair (`emergency-repair.sh`)

Stops restart loops and cleans up the Docker environment.

```bash
./repair-scripts/emergency-repair.sh
```

**Actions:**
- Stops all containers gracefully
- Removes failed containers
- Cleans up Docker resources
- Fixes Docker permissions
- Creates system backup
- Prepares for clean restart

### 3. Manual Initialization (`manual-init.sh`)

Initializes all configurations and dependencies manually.

```bash
./repair-scripts/manual-init.sh
```

**Actions:**
- Creates required directory structure
- Generates SSL certificates
- Creates Kasm configurations
- Sets up database configurations
- Creates nginx configurations
- Initializes Empire configurations
- Fixes all file permissions
- Validates configurations

### 4. Sequential Startup (`sequential-startup.sh`)

Starts services in proper dependency order with health checks.

```bash
./repair-scripts/sequential-startup.sh
```

**Startup Phases:**
1. **Core Infrastructure**: Databases and cache services
2. **Self-Healing Service**: RTPI healer
3. **Application Services**: Kasm, SysReptor, Empire
4. **Supporting Services**: Proxy, tools, utilities

### 5. Health Validation (`health-validator.sh`)

Comprehensive health checks for all services and infrastructure.

```bash
./repair-scripts/health-validator.sh
```

**Health Check Phases:**
1. **Container Health**: Status and health checks
2. **Database Connectivity**: PostgreSQL connections
3. **Redis Connectivity**: Cache service connections
4. **Service Endpoints**: HTTP/HTTPS endpoint testing
5. **Infrastructure**: Networks, volumes, resources

## Quick Start Guide

### For Immediate Repair

If you need to fix the restart loops immediately:

```bash
# Navigate to RTPI-PEN directory
cd /path/to/rtpi-pen

# Run the main repair tool
./repair-scripts/rtpi-pen-repair.sh

# Select option 1 for Full Repair
```

### For Step-by-Step Repair

If you prefer to run individual phases:

```bash
# Step 1: Emergency repair
./repair-scripts/emergency-repair.sh

# Step 2: Initialize configurations
./repair-scripts/manual-init.sh

# Step 3: Start services
./repair-scripts/sequential-startup.sh

# Step 4: Validate health
./repair-scripts/health-validator.sh
```

## Service Access Points

After successful repair, these services will be available:

- **Kasm Workspaces**: https://localhost:8443
- **SysReptor**: http://localhost:7777
- **Empire C2**: http://localhost:1337
- **Orchestrator**: http://localhost:9444
- **Healer API**: http://localhost:8888/health
- **Main Proxy**: https://localhost:443

## Troubleshooting

### Common Issues and Solutions

#### 1. Permission Denied Errors
```bash
# Fix Docker socket permissions
sudo chmod 666 /var/run/docker.sock

# Run manual initialization
./repair-scripts/manual-init.sh
```

#### 2. Containers Still Restarting
```bash
# Check container logs
sudo docker logs <container_name>

# Run emergency repair
./repair-scripts/emergency-repair.sh
```

#### 3. Service Endpoints Not Responding
```bash
# Check if containers are running
sudo docker ps

# Validate system health
./repair-scripts/health-validator.sh
```

#### 4. Database Connection Issues
```bash
# Check database container
sudo docker logs kasm_db

# Restart database services
sudo docker restart kasm_db sysreptor-db rtpi-database
```

### Quick Recovery Scripts

The repair solution also creates these helper scripts:

#### Restart Failed Services
```bash
./repair-scripts/restart-failed-services.sh
```

#### Emergency Recovery
```bash
./repair-scripts/emergency-repair.sh
```

## Prerequisites

- **Docker** with **Docker Compose plugin**
- **sudo** privileges
- **OpenSSL** for certificate generation
- **curl** for endpoint testing
- **bash** shell

## File Structure

```
repair-scripts/
├── rtpi-pen-repair.sh          # Main orchestrator
├── emergency-repair.sh         # Emergency cleanup
├── manual-init.sh             # Configuration initialization
├── sequential-startup.sh      # Sequential service startup
├── health-validator.sh        # Health validation
├── restart-failed-services.sh # Auto-generated quick restart
└── README.md                  # This file
```

## Advanced Usage

### Custom Repair Phases

You can run specific repair phases using the main orchestrator:

```bash
./repair-scripts/rtpi-pen-repair.sh
# Select option 6 for Custom Repair
# Enter phase numbers: 1 3 4 (for emergency, startup, validation)
```

### Health Monitoring

Set up periodic health checks:

```bash
# Create a cron job for health monitoring
echo "0 */6 * * * /path/to/rtpi-pen/repair-scripts/health-validator.sh" | crontab -
```

### Automated Recovery

For automated recovery in case of failures:

```bash
# Create a monitoring script
cat > /usr/local/bin/rtpi-monitor.sh << 'EOF'
#!/bin/bash
if ! /path/to/rtpi-pen/repair-scripts/health-validator.sh; then
    /path/to/rtpi-pen/repair-scripts/restart-failed-services.sh
fi
EOF

chmod +x /usr/local/bin/rtpi-monitor.sh
```

## Logs and Reporting

### Log Locations

- **Repair logs**: `/var/log/rtpi-pen-repair/`
- **Healer logs**: `/var/log/rtpi-healer/`
- **Kasm logs**: `/var/log/kasm/`
- **Container logs**: `sudo docker logs <container_name>`

### Health Reports

Health validation generates detailed reports:

```bash
# Reports are saved to /tmp/rtpi-pen-health-report-TIMESTAMP.txt
ls -la /tmp/rtpi-pen-health-report-*.txt
```

## Configuration Files Created

The repair solution creates these critical configuration files:

### Kasm Workspaces
- `/opt/kasm/1.15.0/conf/app/api.app.config.yaml`
- `/opt/kasm/1.15.0/conf/app/agent.app.config.yaml`
- `/opt/kasm/1.15.0/conf/app/manager.app.config.yaml`
- `/opt/kasm/1.15.0/conf/app/share.app.config.yaml`
- `/opt/kasm/1.15.0/conf/app/kasmguac.app.config.yaml`

### Database
- `/opt/kasm/1.15.0/conf/database/postgresql.conf`
- `/opt/kasm/1.15.0/conf/database/pg_hba.conf`
- `/opt/kasm/1.15.0/conf/database/data.sql`

### SSL Certificates
- `/opt/kasm/1.15.0/certs/kasm_nginx.crt`
- `/opt/kasm/1.15.0/certs/kasm_nginx.key`
- `/opt/kasm/1.15.0/certs/db_server.crt`
- `/opt/kasm/1.15.0/certs/db_server.key`

### Empire C2
- `/opt/empire/data/empire.yaml`

## Security Considerations

- SSL certificates are self-signed for development use
- Default passwords are used for initial setup
- File permissions are set to 1000:1000 for container compatibility
- Docker socket access is granted for container management

## Support and Maintenance

### Regular Maintenance

1. **Weekly Health Checks**: Run health validation weekly
2. **Monthly Backups**: Create configuration backups
3. **Log Rotation**: Clean up old logs periodically
4. **Update Monitoring**: Check for container updates

### Getting Help

If you encounter issues:

1. **Check Logs**: Review container and repair logs
2. **Run Health Check**: Use the health validator
3. **Documentation**: Review service-specific documentation
4. **Community**: Check GitHub issues and discussions

## Version History

- **v1.0.0**: Initial release with comprehensive repair solution
  - Emergency repair functionality
  - Manual initialization
  - Sequential startup
  - Health validation
  - Interactive menu system

## Contributing

To improve the repair solution:

1. Test the scripts in your environment
2. Report bugs or issues
3. Suggest enhancements
4. Submit pull requests

## License

This repair solution is part of the RTPI-PEN project and follows the same licensing terms.
