# RTPI-PEN SSL Certificate Automation

This document describes the automated SSL certificate generation and management system for RTPI-PEN using Let's Encrypt and Cloudflare DNS.

## Overview

The SSL automation system provides:
- Automated Let's Encrypt certificate generation
- Cloudflare DNS management for ACME challenges
- Automatic certificate deployment to services
- Certificate renewal and monitoring
- Service-specific domain configuration

## Quick Start

### Basic SSL Deployment

```bash
# Deploy RTPI-PEN with SSL for organization "c3s"
sudo ./build.sh --slug c3s --enable-ssl
```

### Custom Server IP

```bash
# Deploy with custom server IP
sudo ./build.sh --slug demo --enable-ssl --server-ip 192.168.1.100
```

### Standard Deployment (No SSL)

```bash
# Deploy without SSL certificates
sudo ./build.sh
```

## Generated Domains

For slug `c3s`, the following domains are automatically created:

| Service | Domain | Purpose |
|---------|--------|---------|
| Main Dashboard | `c3s.attck-node.net` | Primary interface |
| SysReptor | `c3s-reports.attck-node.net` | Penetration testing reports |
| Empire C2 | `c3s-empire.attck-node.net` | Command & control |
| Portainer | `c3s-mgmt.attck-node.net` | Container management |
| Kasm Workspaces | `c3s-kasm.attck-node.net` | Virtual workspaces |

## Certificate Management Scripts

### 1. Cloudflare DNS Manager (`setup/cloudflare_dns_manager.sh`)

Handles DNS record creation and ACME challenge management.

```bash
# Create DNS A records for services
./setup/cloudflare_dns_manager.sh create-records c3s 192.168.1.100

# Create ACME challenge record
./setup/cloudflare_dns_manager.sh challenge create c3s-reports "challenge_token"

# Delete ACME challenge record
./setup/cloudflare_dns_manager.sh challenge delete c3s-reports

# List DNS records
./setup/cloudflare_dns_manager.sh challenge list c3s-reports
```

### 2. Certificate Manager (`setup/cert_manager.sh`)

Handles SSL certificate generation and deployment.

```bash
# Complete certificate setup
sudo ./setup/cert_manager.sh full-setup c3s

# Generate certificates only
sudo ./setup/cert_manager.sh generate c3s

# Deploy certificates to services
sudo ./setup/cert_manager.sh deploy c3s

# Update service configurations
./setup/cert_manager.sh configure c3s

# Validate certificates
./setup/cert_manager.sh validate c3s

# Setup automatic renewal
sudo ./setup/cert_manager.sh setup-renewal c3s
```

### 3. Certificate Renewal (`setup/cert_renewal.sh`)

Automated certificate renewal and monitoring.

```bash
# Check and renew expiring certificates
sudo ./setup/cert_renewal.sh renew

# Force renewal of all certificates
sudo ./setup/cert_renewal.sh force

# Show certificate status
./setup/cert_renewal.sh status

# Setup automatic renewal cron job
sudo ./setup/cert_renewal.sh setup-cron
```

## Configuration Files

### Cloudflare Configuration

The system uses hardcoded Cloudflare credentials in `setup/cloudflare_dns_manager.sh`:

```bash
CLOUDFLARE_API_TOKEN="<INSERT_HERE>"
DOMAIN="attck-node.net"
EMAIL="attck.community@gmail.com"
```

### Service Configuration Updates

The system automatically updates:

1. **SysReptor** (`configs/rtpi-sysreptor/app.env`):
   - Updates `ALLOWED_HOSTS` with new domain
   - Enables `SECURE_SSL_REDIRECT`

2. **Nginx Proxy** (`services/rtpi-proxy/nginx/conf.d/rtpi-pen.conf`):
   - Configures SSL certificates
   - Sets up HTTPS redirects
   - Configures proxy headers

3. **Docker Compose** (`docker-compose.yml`):
   - Mounts certificate directories
   - Configures SSL volume access

## Certificate Storage

Certificates are stored in:
- **Let's Encrypt location**: `/etc/letsencrypt/live/{slug}-services/`
- **Deployment location**: `/opt/rtpi-pen/certs/{slug}/`

### Certificate Files

| File | Purpose |
|------|---------|
| `fullchain.pem` | Full certificate chain |
| `privkey.pem` | Private key |
| `cert.pem` | Certificate only |
| `chain.pem` | Intermediate certificates |
| `nginx.crt` | Nginx-compatible certificate |
| `nginx.key` | Nginx-compatible private key |

## Automatic Renewal

The system sets up automatic certificate renewal:

1. **Cron Job**: Runs twice daily (00:00 and 12:00)
2. **Renewal Threshold**: Certificates renewed when < 30 days remaining
3. **Service Restart**: Automatically restarts affected services
4. **Logging**: Renewal activities logged to `/var/log/cert-renewal.log`

## Security Features

### SSL Configuration

- **Protocols**: TLSv1.2, TLSv1.3
- **Ciphers**: Modern cipher suites only
- **HSTS**: Enabled with 2-year max-age
- **Certificate Validation**: Automatic chain validation

### DNS Security

- **Challenge Cleanup**: Automatic cleanup of ACME challenge records
- **Propagation Verification**: Waits for DNS propagation before proceeding
- **Error Handling**: Comprehensive error handling and retry logic

## Troubleshooting

### Common Issues

1. **DNS Propagation Delays**:
   ```bash
   # Check DNS propagation manually
   dig +short TXT _acme-challenge.c3s.attck-node.net @1.1.1.1
   ```

2. **Certificate Validation Failures**:
   ```bash
   # Validate certificate manually
   sudo ./setup/cert_manager.sh validate c3s
   ```

3. **Service Configuration Issues**:
   ```bash
   # Check service logs
   docker-compose logs rtpi-proxy
   ```

4. **Renewal Failures**:
   ```bash
   # Check renewal logs
   sudo tail -f /var/log/cert-renewal.log
   ```

### Debug Commands

```bash
# Test certificate generation (dry run)
sudo certbot renew --cert-name c3s-services --dry-run

# Check certificate expiry
openssl x509 -in /etc/letsencrypt/live/c3s-services/fullchain.pem -text -noout | grep "Not After"

# Test DNS resolution
nslookup c3s.attck-node.net

# Check service health
curl -k https://c3s.attck-node.net
```

## Manual Certificate Management

### Emergency Certificate Replacement

If certificates need manual intervention:

1. **Stop services**:
   ```bash
   docker-compose down
   ```

2. **Remove old certificates**:
   ```bash
   sudo rm -rf /etc/letsencrypt/live/{slug}-services
   sudo rm -rf /opt/rtpi-pen/certs/{slug}
   ```

3. **Generate new certificates**:
   ```bash
   sudo ./setup/cert_manager.sh full-setup {slug}
   ```

4. **Restart services**:
   ```bash
   docker-compose up -d
   ```

### Backup and Restore

```bash
# Backup certificates
sudo tar -czf cert-backup-$(date +%Y%m%d).tar.gz /etc/letsencrypt /opt/rtpi-pen/certs

# Restore certificates
sudo tar -xzf cert-backup-YYYYMMDD.tar.gz -C /
```

## Google OIDC Integration

When using SSL, update your Google OIDC configuration:

1. **Authorized JavaScript Origins**:
   - `https://c3s.attck-node.net`
   - `https://c3s-reports.attck-node.net`
   - `https://c3s-mgmt.attck-node.net`

2. **Authorized Redirect URIs**:
   - `https://c3s.attck-node.net/auth/callback`
   - `https://c3s-reports.attck-node.net/auth/callback`

## Monitoring and Alerts

### Certificate Expiry Monitoring

```bash
# Check all certificate status
./setup/cert_renewal.sh status

# Get certificate expiry dates
for cert in /etc/letsencrypt/live/*/fullchain.pem; do
    echo "Certificate: $cert"
    openssl x509 -in "$cert" -text -noout | grep "Not After"
    echo ""
done
```

### Health Checks

The system includes health checks for:
- Certificate validity
- Service availability
- DNS resolution
- SSL handshake success

## Advanced Usage

### Multi-Environment Deployments

```bash
# Development environment
sudo ./build.sh --slug dev --enable-ssl

# Staging environment
sudo ./build.sh --slug staging --enable-ssl

# Production environment
sudo ./build.sh --slug prod --enable-ssl
```

### Custom Domain Configuration

To use a different domain, update the configuration in:
- `setup/cloudflare_dns_manager.sh`
- `setup/cert_manager.sh`
- `build.sh`

## Support

For issues or questions:
1. Check the logs in `/var/log/cert-renewal.log`
2. Run diagnostic commands from the troubleshooting section
3. Review the certificate status with `./setup/cert_renewal.sh status`

## Version Information

- **SSL Automation Version**: 1.0.0
- **Build Script Version**: 1.18.0
- **Compatible RTPI-PEN Version**: 1.17.0+

---

*This documentation is part of the RTPI-PEN SSL automation system. For general RTPI-PEN usage, see the main README.md file.*
