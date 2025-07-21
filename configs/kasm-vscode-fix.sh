#!/bin/bash

# Wait for VNC server to start
sleep 5

# Find the VNC process and restart it without SSL
echo "Fixing KasmVNC SSL configuration..."

# Kill the existing VNC server
pkill -f kasmvnc || true
vncserver -kill :1 || true

# Wait a moment for cleanup
sleep 2

# Restart VNC server without SSL requirement
cd /home/kasm-user

# Remove any existing locks
rm -rf /tmp/.X*-lock /tmp/.X11-unix 2>/dev/null || true
rm -rf $HOME/.vnc/*.pid 2>/dev/null || true

# Create a new xstartup
echo "exit 0" > $HOME/.vnc/xstartup
chmod +x $HOME/.vnc/xstartup

# Start VNC server without SSL requirement by removing -sslOnly flag
export DISPLAY=:1
export VNC_COL_DEPTH=${VNC_COL_DEPTH:-24}
export VNC_RESOLUTION=${VNC_RESOLUTION:-1280x720}
export NO_VNC_PORT=${NO_VNC_PORT:-6901}
export MAX_FRAME_RATE=${MAX_FRAME_RATE:-30}
export KASM_VNC_PATH=${KASM_VNC_PATH:-/usr/share/kasmvnc}

# Restart the VNC server without SSL enforcement
vncserver $DISPLAY -drinode /dev/dri/renderD128 -depth $VNC_COL_DEPTH -geometry $VNC_RESOLUTION -websocketPort $NO_VNC_PORT -httpd ${KASM_VNC_PATH}/www -FrameRate=$MAX_FRAME_RATE -interface 0.0.0.0 -BlacklistThreshold=0 -FreeKeyMappings -select-de manual

echo "KasmVNC SSL fix applied successfully"
