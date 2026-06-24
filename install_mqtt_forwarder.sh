#!/bin/bash

set -e

echo "########################################"
echo "# ChirpStack MQTT Forwarder Installer #"
echo "########################################"

# ----------------------------
# DEFAULT VALUES
# ----------------------------
DEFAULT_GW_IP="192.168.2.1"
DEFAULT_GW_USER="sysadmin"
DEFAULT_MQTT_IP="192.168.2.10"
DEFAULT_MQTT_PORT="1883"

# ----------------------------
# INPUT
# ----------------------------
read -p "Gateway IP [$DEFAULT_GW_IP]: " GW_IP
GW_IP=${GW_IP:-$DEFAULT_GW_IP}

read -p "Gateway User [$DEFAULT_GW_USER]: " GW_USER
GW_USER=${GW_USER:-$DEFAULT_GW_USER}

read -s -p "Gateway Password: " GW_PASS
echo ""

read -p "MQTT Server IP [$DEFAULT_MQTT_IP]: " MQTT_IP
MQTT_IP=${MQTT_IP:-$DEFAULT_MQTT_IP}

read -p "MQTT Port [$DEFAULT_MQTT_PORT]: " MQTT_PORT
MQTT_PORT=${MQTT_PORT:-$DEFAULT_MQTT_PORT}

# ----------------------------
# PACKAGE
# ----------------------------
PKG="chirpstack-mqtt-forwarder_4.3.1-r1_arm926ejste.ipk"
URL="https://artifacts.chirpstack.io/downloads/chirpstack-mqtt-forwarder/vendor/multitech/conduit/$PKG"

echo ""
echo "Downloading package on server..."
wget -q --show-progress -O /tmp/$PKG "$URL"

# ----------------------------
# COPY TO GATEWAY
# ----------------------------
echo "Copying package to gateway..."
sshpass -p "$GW_PASS" scp -o StrictHostKeyChecking=no /tmp/$PKG $GW_USER@$GW_IP:/tmp/

# ----------------------------
# INSTALL + CONFIGURE
# ----------------------------
echo "Installing and configuring on gateway..."

sshpass -p "$GW_PASS" ssh -tt -o StrictHostKeyChecking=no $GW_USER@$GW_IP << EOF
set -e

echo "Installing package (ignore if already installed)..."
echo "$GW_PASS" | sudo -S opkg install /tmp/$PKG || true

CONF="/var/config/chirpstack-mqtt-forwarder/ap1/chirpstack-mqtt-forwarder.toml"

if [ -f "\$CONF" ]; then
    echo "Configuring MQTT..."
    echo "$GW_PASS" | sudo -S sed -i "s#^server=.*#server=\"tcp://$MQTT_IP:$MQTT_PORT\"#g" "\$CONF"
else
    echo "ERROR: Config file not found!"
    exit 1
fi

echo "Restarting forwarder..."
echo "$GW_PASS" | sudo -S /etc/init.d/chirpstack-mqtt-forwarder-ap1 restart || true

echo "DONE"
EOF

echo ""
echo "########################################"
echo "Installation finished successfully"
echo "########################################"
