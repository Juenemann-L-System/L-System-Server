#!/usr/bin/env bash

set -euo pipefail

########################################
# CONFIG INPUT
########################################

read -rp "Gateway IP Address: " GW_IP
read -rp "Gateway USER: " GW_USER
read -rsp "User Password (for sudo only on gateway): " GW_PASS
echo ""
read -rp "MQTT Server IP: " MQTT_IP
read -rp "MQTT Server Port (1883): " MQTT_PORT

echo ""
echo "Install (i) or Update config only (u): "
read -rp "> " MODE

########################################
# BASIC CHECKS
########################################

SSH_OPTS="-o StrictHostKeyChecking=no"

echo "[INFO] Checking gateway SSH..."

ssh ${SSH_OPTS} ${GW_USER}@${GW_IP} "echo ok" >/dev/null 2>&1 || {
    echo "[ERROR] Gateway not reachable via SSH"
    exit 1
}

echo "[OK] Gateway reachable"

########################################
# DETECT ARCH ON GATEWAY
########################################

echo "[INFO] Detecting gateway type..."

GATEWAY_INFO=$(ssh ${SSH_OPTS} ${GW_USER}@${GW_IP} "cat /etc/os-release 2>/dev/null || uname -a")

echo "$GATEWAY_INFO" | grep -qi mtcap && GW_TYPE="mtcap" || GW_TYPE="generic"

echo "[INFO] Gateway type: $GW_TYPE"

########################################
# DOWNLOAD IPK ON SERVER
########################################

TMP_IPK="/tmp/chirpstack-mqtt-forwarder.ipk"

echo "[INFO] Downloading package..."

if [[ "$GW_TYPE" == "mtcap" ]]; then
    PKG_URL="https://artifacts.chirpstack.io/downloads/chirpstack-mqtt-forwarder/vendor/multitech/mtcap/chirpstack-mqtt-forwarder_4.3.1-r1_mtcap.ipk"
else
    PKG_URL="https://artifacts.chirpstack.io/downloads/chirpstack-mqtt-forwarder/vendor/multitech/conduit_ap3/chirpstack-mqtt-forwarder_4.3.1-r1_mtcap3.ipk"
fi

wget -qO "$TMP_IPK" "$PKG_URL"

echo "[OK] Package downloaded"

########################################
# COPY TO GATEWAY
########################################

echo "[INFO] Copying package to gateway..."

scp ${SSH_OPTS} "$TMP_IPK" ${GW_USER}@${GW_IP}:/tmp/

########################################
# INSTALL OR UPDATE ON GATEWAY
########################################

if [[ "$MODE" == "i" ]]; then
    ACTION="install"
else
    ACTION="update config only"
fi

echo "[INFO] Running remote action: $ACTION"

ssh ${SSH_OPTS} ${GW_USER}@${GW_IP} bash -s <<EOF
set -e

echo "[GATEWAY] Installing package..."

echo "$GW_PASS" | sudo -S opkg install /tmp/$(basename "$TMP_IPK") || true

echo "[GATEWAY] Configuring MQTT..."

CFG="/var/config/chirpstack-mqtt-forwarder/ap1/chirpstack-mqtt-forwarder.toml"

if [ -f "\$CFG" ]; then
    sed -i "s#server=\"tcp://.*\"#server=\"tcp://${MQTT_IP}:${MQTT_PORT}\"#" "\$CFG"
fi

echo "[GATEWAY] Restarting services..."

if command -v monit >/dev/null 2>&1; then
    echo "$GW_PASS" | sudo -S monit restart chirpstack-mqtt-forwarder || true
else
    echo "$GW_PASS" | sudo -S /etc/init.d/chirpstack-mqtt-forwarder-ap1 restart || true
fi

echo "[GATEWAY] Done."
EOF

echo "[OK] Completed"
