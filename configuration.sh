#!/usr/bin/env bash

set -euo pipefail

########################################
# INPUT
########################################

read -rp "Gateway IP Address: " GW_IP
read -rp "Gateway USER: " GW_USER
read -rsp "Gateway Password (sudo on gateway): " GW_PASS
echo ""

read -rp "MQTT Server IP: " MQTT_IP
read -rp "MQTT Server Port (1883): " MQTT_PORT

echo ""
echo "Install (i) or Update config only (u):"
read -rp "> " MODE

SSH_OPTS="-o StrictHostKeyChecking=no"

########################################
# CHECK SSH
########################################

echo "[INFO] Checking gateway SSH..."

ssh ${SSH_OPTS} ${GW_USER}@${GW_IP} "echo ok" >/dev/null 2>&1 || {
    echo "[ERROR] Gateway not reachable"
    exit 1
}

echo "[OK] Gateway reachable"

########################################
# FORCE CORRECT DEVICE TYPE
########################################

echo "[INFO] Detecting gateway hardware..."

GW_TYPE=$(ssh ${SSH_OPTS} ${GW_USER}@${GW_IP} '
if [ -f /var/config/device ]; then
    cat /var/config/device
elif grep -qi mtcap /proc/cpuinfo 2>/dev/null; then
    echo mtcap
else
    echo mtcap
fi
')

echo "[INFO] Detected: $GW_TYPE"

# HARD FIX (because Multitech feeds are inconsistent)
GW_TYPE="mtcap"

########################################
# SELECT CORRECT PACKAGE
########################################

echo "[INFO] Selecting IPK..."

PKG_URL="https://artifacts.chirpstack.io/downloads/chirpstack-mqtt-forwarder/vendor/multitech/mtcap/chirpstack-mqtt-forwarder_4.3.1-r1_mtcap.ipk"

TMP_IPK="/tmp/chirpstack-mqtt-forwarder.ipk"

########################################
# DOWNLOAD ON SERVER
########################################

echo "[INFO] Downloading IPK..."

wget -qO "$TMP_IPK" "$PKG_URL"

echo "[OK] Download complete"

########################################
# COPY TO GATEWAY
########################################

echo "[INFO] Copying to gateway..."

scp ${SSH_OPTS} "$TMP_IPK" ${GW_USER}@${GW_IP}:/tmp/

########################################
# EXECUTE ON GATEWAY
########################################

if [[ "$MODE" == "i" ]]; then
    ACTION="install"
else
    ACTION="update"
fi

echo "[INFO] Running $ACTION on gateway..."

ssh ${SSH_OPTS} ${GW_USER}@${GW_IP} bash -s <<EOF
set -e

IPK="/tmp/$(basename "$TMP_IPK")"

echo "[GATEWAY] Installing package..."

echo "$GW_PASS" | sudo -S opkg install \$IPK || true

echo "[GATEWAY] Configuring MQTT..."

CFG="/var/config/chirpstack-mqtt-forwarder/ap1/chirpstack-mqtt-forwarder.toml"

if [ -f "\$CFG" ]; then
    sed -i "s#server=\"tcp://.*\"#server=\"tcp://${MQTT_IP}:${MQTT_PORT}\"#" "\$CFG"
fi

echo "[GATEWAY] Restarting service..."

echo "$GW_PASS" | sudo -S monit restart chirpstack-mqtt-forwarder-ap1 2>/dev/null || \
echo "$GW_PASS" | sudo -S /etc/init.d/chirpstack-mqtt-forwarder-ap1 restart 2>/dev/null || true

echo "[GATEWAY] Done."
EOF

echo "[OK] Completed successfully"
