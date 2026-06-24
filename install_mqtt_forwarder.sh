#!/bin/bash

set -e

echo "########################################"
echo "# ChirpStack MQTT Forwarder Installer #"
echo "########################################"

# ----------------------------
# 1. Eingaben
# ----------------------------
read -p "Gateway IP: " GW_IP
read -p "Gateway User: " GW_USER
read -s -p "Gateway Password: " GW_PASS
echo ""

read -p "MQTT Server IP: " MQTT_IP
read -p "MQTT Port (default 1883): " MQTT_PORT
MQTT_PORT=${MQTT_PORT:-1883}

# ----------------------------
# 2. Paket definieren (korrekt für dein Gerät)
# ----------------------------
PKG="chirpstack-mqtt-forwarder_4.3.1-r1_arm926ejste.ipk"
URL="https://artifacts.chirpstack.io/downloads/chirpstack-mqtt-forwarder/vendor/multitech/conduit/$PKG"

echo ""
echo "Downloading package on server..."
wget -q --show-progress -O /tmp/$PKG "$URL"

# ----------------------------
# 3. Copy to gateway
# ----------------------------
echo "Copying package to gateway..."
sshpass -p "$GW_PASS" scp -o StrictHostKeyChecking=no /tmp/$PKG $GW_USER@$GW_IP:/tmp/

# ----------------------------
# 4. Install on gateway
# ----------------------------
echo "Installing on gateway..."
sshpass -p "$GW_PASS" ssh -o StrictHostKeyChecking=no $GW_USER@$GW_IP << EOF
set -e

echo "Installing package..."
sudo opkg install /tmp/$PKG

echo "Configuring MQTT..."

# AP1 konfigurieren (Standard verwenden wir AP1)
CONF="/var/config/chirpstack-mqtt-forwarder/ap1/chirpstack-mqtt-forwarder.toml"

if [ -f "\$CONF" ]; then
    sed -i "s#^server=.*#server=\"tcp://$MQTT_IP:$MQTT_PORT\"#g" \$CONF
    echo "MQTT configured in AP1"
else
    echo "Config not found!"
    exit 1
fi

echo "Restarting service..."
sudo /etc/init.d/chirpstack-mqtt-forwarder-ap1 restart || true

echo "Done."
EOF

echo ""
echo "########################################"
echo "Installation completed"
echo "########################################"
