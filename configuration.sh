#!/bin/bash
# This script installs or updates the chirpstack-mqtt-forwarder on the remote gateway.

# Check if sshpass is installed.
if ! command -v sshpass &> /dev/null; then
    echo "Error: sshpass is not installed."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "Please install it using Homebrew:"
        echo "  brew install sshpass"
    else
        echo "Please install it using apt (or your distro's package manager):"
        echo "  sudo apt install sshpass"
    fi
    exit 1
fi

# 1. Ask for credentials and settings.
read -p "Gateway IP Address: " GatewayIP
read -p "Gateway USER: " GatewayUSER
read -s -p "User Password: " GatewayUSERPASS
echo ""
read -p "MQTT Server IP (chirpstack server): " mgttSERVERIP
read -p "MQTT Server Port (Default 1883): " mqttSERVERPORT

echo ""
echo "Do you want to perform a full installation or update configuration only?"
echo "  i - Install (download and install MQTT forwarder, then update config)"
echo "  u - Update config only"
read -p "Enter i or u: " choice

if [ "$choice" == "i" ]; then
    INSTALL=true
elif [ "$choice" == "u" ]; then
    INSTALL=false
else
    echo "Invalid input. Exiting..."
    exit 1
fi

# Define common SSH options.
SSH_OPTS="-o StrictHostKeyChecking=no"

# 2. If installation is chosen, connect via SSH and download/install MQTT forwarder.
if [ "$INSTALL" = true ]; then
    sshpass -p "$GatewayUSERPASS" ssh $SSH_OPTS ${GatewayUSER}@${GatewayIP} << 'EOF'
echo "Changing to /tmp directory..."
cd /tmp
echo "Downloading chirpstack-mqtt-forwarder..."
wget --no-check-certificate https://artifacts.chirpstack.io/downloads/chirpstack-mqtt-forwarder/vendor/multitech/conduit/chirpstack-mqtt-forwarder_4.5.1-r1_arm926ejste.ipk
echo "Installing chirpstack-mqtt-forwarder..."
sudo opkg install chirpstack-mqtt-forwarder_4.3.1-r1_mtcap3.ipk
EOF
fi

# 3. Adjust the configuration of the MQTT forwarder.
# The configuration file is located at:
#   /var/config/chirpstack-mqtt-forwarder/chirpstack-mqtt-forwarder.toml
#
# This sed command restricts the replacement to the [mqtt] section.
sshpass -p "$GatewayUSERPASS" ssh $SSH_OPTS ${GatewayUSER}@${GatewayIP} "echo '${GatewayUSERPASS}' | sudo -S sed -i '/^\[mqtt\]/,/^\[/ s#^\([[:space:]]*server=\"tcp://\)[^\"]*\(.*\)#\1${mgttSERVERIP}:${mqttSERVERPORT}\2#' /var/config/chirpstack-mqtt-forwarder/chirpstack-mqtt-forwarder.toml"

# 4. Start or restart the MQTT forwarder.
if [ "$INSTALL" = true ]; then
    echo "Starting chirpstack-mqtt-forwarder..."
    sshpass -p "$GatewayUSERPASS" ssh $SSH_OPTS ${GatewayUSER}@${GatewayIP} "echo '${GatewayUSERPASS}' | sudo -S monit start chirpstack-mqtt-forwarder"
else
    echo "Restarting chirpstack-mqtt-forwarder..."
    sshpass -p "$GatewayUSERPASS" ssh $SSH_OPTS ${GatewayUSER}@${GatewayIP} "echo '${GatewayUSERPASS}' | sudo -S monit restart chirpstack-mqtt-forwarder"
fi

echo "Operation completed."
