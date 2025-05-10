#!/bin/bash

# Variables
echo "What are the subdomains? (ex. attck-sub1 attck-sub2)"
read -p "Please provide each subdomain separated by a space: " -a SUBDOMAINS

echo "What is your email?"
read -p "Please provide the email associated with your API key: " EMAIL

echo "What is the domain root? (ex. attck.community)"
read -p "Please provide the root domain: " DOMAINROOT

# Loop through each subdomain and execute the certbot command
for SUBDOMAIN in "${SUBDOMAINS[@]}"; do
    echo "Processing subdomain: ${SUBDOMAIN}.${DOMAINROOT}"

    # Execute certbot command for each subdomain
    certbot certonly --manual --preferred-challenges=dns --email "${EMAIL}" --server https://acme-v02.api.letsencrypt.org/directory --agree-tos -d "${SUBDOMAIN}.${DOMAINROOT}"

    # Output the path to certs and key files
    echo "Path to Certs: /etc/letsencrypt/live/${DOMAINROOT}/"
    echo "Certificate is saved at: /etc/letsencrypt/live/${DOMAINROOT}/fullchain.pem"
    echo "Key is saved at: /etc/letsencrypt/live/${DOMAINROOT}/privkey.pem"

    # Example for setting up HTTPS listeners in MSFConsole
    echo "For setting up HTTPS Listeners in MSFConsole:"
    echo "cat /etc/letsencrypt/live/${DOMAINROOT}/fullchain.pem /etc/letsencrypt/live/${DOMAINROOT}/privkey.pem > /opt/ssl/${SUBDOMAIN}-certkey.pem"
    echo ""
done

echo "All subdomains processed!"
