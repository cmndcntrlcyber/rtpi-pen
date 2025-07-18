# RTPI-PEN Security Tools Service
FROM ubuntu:22.04

# Prevent interactive prompts during installation
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Create application directories
RUN mkdir -p /opt/tools /var/log/rtpi

# Add external repositories
RUN apt-get update && apt-get install -y \
    curl wget gnupg lsb-release ca-certificates software-properties-common \
    && rm -rf /var/lib/apt/lists/*

# Add Microsoft PowerShell repository
RUN curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/microsoft.gpg \
    && echo "deb [arch=amd64,arm64,armhf signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/microsoft-ubuntu-jammy-prod jammy main" > /etc/apt/sources.list.d/microsoft.list

# Install base system packages
RUN apt-get update && apt-get install -y \
    # Basic system tools
    build-essential git vim nano htop sudo \
    # Security and networking tools (available in Ubuntu repos)
    nmap hashcat hydra proxychains4 \
    mingw-w64 wine wireshark python3-impacket \
    nbtscan smbclient net-tools \
    # Development tools
    python3 python3-pip python3-venv python-is-python3 jython pipx \
    default-jdk golang-go \
    # SSL/TLS tools
    certbot \
    # Additional tools
    powershell \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js (latest LTS) - Clean installation
RUN apt-get purge -y nodejs npm libnode-dev node-* || true \
    && rm -rf /usr/include/node /usr/lib/node_modules /etc/apt/sources.list.d/nodesource.list || true \
    && curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - \
    && apt-get install -y nodejs

# Install Python packages for red team operations
RUN pip3 install --no-cache-dir \
    pwntools pycryptodome cryptography requests pyOpenSSL \
    impacket bloodhound

# Install Metasploit Framework
RUN curl https://raw.githubusercontent.com/rapid7/metasploit-omnibus/master/config/templates/metasploit-framework-wrappers/msfupdate.erb > msfinstall \
    && chmod 755 msfinstall \
    && ./msfinstall \
    && rm msfinstall

# Install additional red team tools
RUN cd /opt/tools && \
    git clone https://github.com/PowerShellMafia/PowerSploit.git && \
    git clone https://github.com/S3cur3Th1sSh1t/WinPwn.git && \
    git clone https://github.com/BloodHoundAD/BloodHound.git && \
    git clone https://github.com/offensive-security/exploitdb.git && \
    ln -sf /opt/tools/exploitdb/searchsploit /usr/local/bin/searchsploit

# Copy custom tools
COPY tools/ /opt/tools/custom/

# Create a non-root user for running tools
RUN useradd -m -s /bin/bash rtpi-tools && \
    echo "rtpi-tools ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Create entrypoint script
RUN cat > /usr/local/bin/tools-entrypoint.sh << 'EOF'
#!/bin/bash
set -e

echo "🔧 RTPI-PEN Security Tools Container Ready"
echo "Available tools:"
echo "  - Metasploit Framework: msfconsole"
echo "  - Nmap: nmap"
echo "  - Hashcat: hashcat"
echo "  - Hydra: hydra"
echo "  - Bloodhound tools: bloodhound-python"
echo "  - PowerShell: pwsh"
echo "  - Custom tools in /opt/tools/"

# Keep container running
exec "$@"
EOF

RUN chmod +x /usr/local/bin/tools-entrypoint.sh

# Switch to non-root user
USER rtpi-tools
WORKDIR /home/rtpi-tools

# Expose common tool ports (if needed for specific tools)
EXPOSE 4444 5555

# Health check
HEALTHCHECK --interval=60s --timeout=10s --retries=3 \
    CMD echo "Tools container is healthy"

ENTRYPOINT ["/usr/local/bin/tools-entrypoint.sh"]
CMD ["/bin/bash"]
