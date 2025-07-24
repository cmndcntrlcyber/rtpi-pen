#!/bin/bash

# SysReptor Encryption Key Fix Script
# Prevents malformed base64 encryption keys in auto-generated config

echo "========================================"
echo "🔧 SysReptor Encryption Key Fixer"
echo "========================================"

APP_ENV_FILE="configs/rtpi-sysreptor/app.env"

if [ ! -f "$APP_ENV_FILE" ]; then
    echo "❌ Error: $APP_ENV_FILE not found"
    exit 1
fi

echo "📁 Checking $APP_ENV_FILE for malformed encryption keys..."

# Check if the current encryption key has correct base64 padding
CURRENT_KEY=$(grep -oP 'ENCRYPTION_KEYS=\[{"id":"[^"]+","key":"\K[^"]+' "$APP_ENV_FILE")

if [ -z "$CURRENT_KEY" ]; then
    echo "❌ Error: Could not extract encryption key from config"
    exit 1
fi

echo "Current key: $CURRENT_KEY"

# Try to decode the base64 key to validate it
if echo "$CURRENT_KEY" | base64 -d > /dev/null 2>&1; then
    echo "✅ Current encryption key is valid base64"
    exit 0
else
    echo "⚠️ Current encryption key has invalid base64 padding"
    echo "🔄 Generating new valid encryption key..."
    
    # Generate a new 32-byte key and encode it properly
    NEW_KEY=$(python3 -c "import base64, secrets; print(base64.b64encode(secrets.token_bytes(32)).decode())")
    
    if [ -z "$NEW_KEY" ]; then
        echo "❌ Error: Failed to generate new encryption key"
        exit 1
    fi
    
    echo "New key: $NEW_KEY"
    
    # Create backup
    cp "$APP_ENV_FILE" "$APP_ENV_FILE.backup.$(date +%Y%m%d-%H%M%S)"
    echo "📄 Backup created: $APP_ENV_FILE.backup.$(date +%Y%m%d-%H%M%S)"
    
    # Replace the malformed key with the new one
    sed -i "s|\"key\":\"$CURRENT_KEY\"|\"key\":\"$NEW_KEY\"|g" "$APP_ENV_FILE"
    
    echo "✅ Encryption key updated successfully"
    echo "🔄 Restarting sysreptor-app container to apply changes..."
    
    docker compose restart sysreptor-app
    
    echo "✅ SysReptor encryption key fix completed!"
    echo ""
    echo "💡 To prevent this issue in the future:"
    echo "   - Run this script after any build process that regenerates app.env"
    echo "   - Consider updating the build process to generate proper base64 keys"
fi
