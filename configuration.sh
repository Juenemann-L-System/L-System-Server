#!/usr/bin/env bash
set -euo pipefail

############################
# CONFIG
############################

IPK_URL="https://artifacts.chirpstack.io/downloads/chirpstack-mqtt-forwarder/vendor/multitech/conduit_ap3/chirpstack-mqtt-forwarder_4.3.1-r1_mtcap3.ipk"
IPK_FILE="chirpstack-mqtt-forwarder.ipk"

SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=5"

############################
# INPUTS
############################

read -p "Gateway IP Address: " GATEWAY_IP
read -p "Gateway USER: " GATEWAY_USER
read -s -p "Gateway Password: " GATEWAY_PASS
echo ""

read -p "MQTT Server IP: " MQTT_IP
read -p "MQTT Server Port (1883): " MQTT_PORT

read -p "Install (i) or Update config only (u): " MODE

############################
# CHECK GATEWAY REACHABILITY
############################

echo "[INFO] Checking gateway connectivity..."

if ! sshpass -p "$GATEWAY_PASS" ssh $SSH_OPTS ${GATEWAY_USER}@${GATEWAY_IP} "echo ok" >/dev/null 2>&1; then
    echo "[ERROR] Gateway not reachable via SSH"
    exit 1
fi

echo "[OK] Gateway reachable"

############################
# INSTALL MODE
############################

if [[ "$MODE" == "i" ]]; then

    echo "[INFO] Downloading IPK on server..."
    curl -L --fail "$IPK_URL" -o "$IPK_FILE"

    echo "[INFO] Copying IPK to gateway..."
    sshpass -p "$GATEWAY_PASS" scp $SSH_OPTS "$IPK_FILE" \
        ${GATEWAY_USER}@${GATEWAY_IP}:/tmp/

    echo "[INFO] Installing on gateway..."
    sshpass -p "$GATEWAY_PASS" ssh $SSH_OPTS ${GATEWAY_USER}@${GATEWAY_IP} << EOF
echo "$GATEWAY_PASS" | sudo -S opkg install /tmp/$IPK_FILE
EOF

fi

############################
# CONFIG UPDATE
############################

echo "[INFO] Updating MQTT config..."

sshpass -p "$GATEWAY_PASS" ssh $SSH_OPTS ${GATEWAY_USER}@${GATEWAY_IP} << EOF

CONFIG="/var/config/chirpstack-mqtt-forwarder/chirpstack-mqtt-forwarder.toml"

if [ ! -f "\$CONFIG" ]; then
    echo "[ERROR] Config file not found: \$CONFIG"
    exit 1
fi

echo "$GATEWAY_PASS" | sudo -S sed -i '/^\[mqtt\]/,/^\[/ s#^\([[:space:]]*server=\"tcp://\)[^\"]*\(.*\)#\1${MQTT_IP}:${MQTT_PORT}\2#' "\$CONFIG"

EOF

############################
# RESTART SERVICE
############################

echo "[INFO] Restarting service..."

sshpass -p "$GATEWAY_PASS" ssh $SSH_OPTS ${GATEWAY_USER}@${GATEWAY_IP} << EOF

if command -v monit >/dev/null 2>&1; then
    echo "$GATEWAY_PASS" | sudo -S monit restart chirpstack-mqtt-forwarder || true
else
    echo "[WARN] monit not found, trying service restart"
    echo "$GATEWAY_PASS" | sudo -S /etc/init.d/chirpstack-mqtt-forwarder restart || true
fi

EOF

echo "[DONE]"
