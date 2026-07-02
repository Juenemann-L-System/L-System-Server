#!/bin/bash
# ChirpStack MQTT Forwarder - Offline Gateway Install (Variant A)

set -e

# Check sshpass
if ! command -v sshpass &> /dev/null; then
    echo "Error: sshpass is not installed."
    echo "Install with: sudo apt install sshpass"
    exit 1
fi

# 1. Inputs
read -p "Gateway IP Address: " GatewayIP
read -p "Gateway USER: " GatewayUSER
read -s -p "User Password: " GatewayUSERPASS
echo ""

read -p "MQTT Server IP (chirpstack server): " mqttSERVERIP
read -p "MQTT Server Port (Default 1883): " mqttSERVERPORT

echo ""
echo "Do you want:"
echo "  i - Install (download on server, install on gateway)"
echo "  u - Update config only"
read -p "Enter i or u: " choice

if [ "$choice" == "i" ]; then
    INSTALL=true
elif [ "$choice" == "u" ]; then
    INSTALL=false
else
    echo "Invalid input"
    exit 1
fi

SSH_OPTS="-o StrictHostKeyChecking=no"

IPK_FILE="chirpstack-mqtt-forwarder_4.3.1-r1_mtcap3.ipk"
DOWNLOAD_URL="https://artifacts.chirpstack.io/downloads/chirpstack-mqtt-forwarder/vendor/multitech/conduit_ap3/${IPK_FILE}"

# 2. INSTALL MODE (server download → push → install)
if [ "$INSTALL" = true ]; then

    echo "Downloading package on SERVER..."
    wget -q --no-check-certificate "$DOWNLOAD_URL" -O "$IPK_FILE"

    echo "Copying package to gateway..."
    sshpass -p "$GatewayUSERPASS" scp $SSH_OPTS "$IPK_FILE" \
        ${GatewayUSER}@${GatewayIP}:/tmp/

    echo "Installing on gateway..."
    sshpass -p "$GatewayUSERPASS" ssh $SSH_OPTS ${GatewayUSER}@${GatewayIP} << EOF
echo "Installing MQTT forwarder..."
sudo opkg install /tmp/${IPK_FILE}
EOF

fi

# 3. CONFIG UPDATE (always server → gateway)
echo "Updating MQTT configuration..."

sshpass -p "$GatewayUSERPASS" ssh $SSH_OPTS ${GatewayUSER}@${GatewayIP} \
"echo '${GatewayUSERPASS}' | sudo -S sed -i '/^\[mqtt\]/,/^\[/ s#^\([[:space:]]*server=\"tcp://\)[^\"]*\(.*\)#\1${mqttSERVERIP}:${mqttSERVERPORT}\2#' \
/var/config/chirpstack-mqtt-forwarder/chirpstack-mqtt-forwarder.toml"

# 4. RESTART
if [ "$INSTALL" = true ]; then
    echo "Starting service..."
    sshpass -p "$GatewayUSERPASS" ssh $SSH_OPTS ${GatewayUSER}@${GatewayIP} \
        "echo '${GatewayUSERPASS}' | sudo -S monit start chirpstack-mqtt-forwarder"
else
    echo "Restarting service..."
    sshpass -p "$GatewayUSERPASS" ssh $SSH_OPTS ${GatewayUSER}@${GatewayIP} \
        "echo '${GatewayUSERPASS}' | sudo -S monit restart chirpstack-mqtt-forwarder"
fi

echo "DONE."
