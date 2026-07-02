#!/usr/bin/env bash
set -euo pipefail

########################################
# INPUT
########################################

read -rp "Gateway IP Address: " GW_IP
read -rp "Gateway USER: " GW_USER
read -rsp "Gateway Password: " GW_PASS
echo ""

read -rp "MQTT Server IP: " MQTT_IP
read -rp "MQTT Server Port (1883): " MQTT_PORT

echo ""
echo "Install (i) or Update config only (u):"
read -rp "> " MODE

########################################
# SSH helper (IMPORTANT FIX)
########################################

SSH="sshpass -p \"$GW_PASS\" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
SCP="sshpass -p \"$GW_PASS\" scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

echo "[INFO] Checking gateway..."

$SSH ${GW_USER}@${GW_IP} "echo ok" >/dev/null
echo "[OK] Gateway reachable"

########################################
# Detect architecture (FIX for your error)
########################################

ARCH=$($SSH ${GW_USER}@${GW_IP} "uname -m" | tr -d '\r')

echo "[INFO] Gateway arch: $ARCH"

########################################
# Choose correct package
########################################

if [[ "$ARCH" == "armv7l" || "$ARCH" == "mips" ]]; then
  PKG_URL="https://artifacts.chirpstack.io/downloads/chirpstack-mqtt-forwarder/vendor/multitech/conduit_ap3/chirpstack-mqtt-forwarder_4.3.1-r1_mtcap3.ipk"
else
  echo "[ERROR] Unsupported architecture for this IPK: $ARCH"
  echo "        Your previous error confirms mismatch."
  exit 1
fi

PKG="/tmp/chirpstack-mqtt-forwarder.ipk"

########################################
# INSTALL MODE
########################################

if [[ "$MODE" == "i" ]]; then

  echo "[INFO] Downloading package..."
  curl -L "$PKG_URL" -o "$PKG"

  echo "[INFO] Uploading package..."
  $SCP "$PKG" ${GW_USER}@${GW_IP}:/tmp/

  echo "[INFO] Installing on gateway..."

  $SSH ${GW_USER}@${GW_IP} "echo '$GW_PASS' | sudo -S sh -c '
    set -e

    echo \"[GATEWAY] Installing package...\"

    if command -v opkg >/dev/null 2>&1; then
        opkg install /tmp/chirpstack-mqtt-forwarder.ipk || true
    fi

    CFG1=/var/config/chirpstack-mqtt-forwarder/chirpstack-mqtt-forwarder.toml
    CFG2=/etc/chirpstack-mqtt-forwarder/chirpstack-mqtt-forwarder.toml

    CFG=\"\"
    if [ -f \$CFG1 ]; then CFG=\$CFG1; fi
    if [ -f \$CFG2 ]; then CFG=\$CFG2; fi

    if [ -n \"\$CFG\" ]; then
        echo \"[GATEWAY] Updating MQTT config: \$CFG\"
        sed -i \"s#server=.*#server=\\\"tcp://${MQTT_IP}:${MQTT_PORT}\\\"#\" \$CFG || true
    fi

    echo \"[GATEWAY] Restarting services...\"

    if [ -x /etc/init.d/lora-network-server ]; then
        /etc/init.d/lora-network-server restart || true
    fi

    if [ -x /etc/init.d/chirpstack-mqtt-forwarder-ap1 ]; then
        /etc/init.d/chirpstack-mqtt-forwarder-ap1 restart || true
    fi

    if command -v monit >/dev/null 2>&1; then
        monit restart chirpstack-mqtt-forwarder || true
    fi
  '"

fi

########################################
# UPDATE MODE
########################################

if [[ "$MODE" == "u" ]]; then

  echo "[INFO] Updating config only..."

  $SSH ${GW_USER}@${GW_IP} "echo '$GW_PASS' | sudo -S sh -c '
    CFG=/var/config/chirpstack-mqtt-forwarder/chirpstack-mqtt-forwarder.toml

    if [ -f \$CFG ]; then
        sed -i \"s#server=.*#server=\\\"tcp://${MQTT_IP}:${MQTT_PORT}\\\"#\" \$CFG
        echo \"[GATEWAY] Config updated\"
    else
        echo \"[WARN] Config not found\"
    fi

    if [ -x /etc/init.d/chirpstack-mqtt-forwarder-ap1 ]; then
        /etc/init.d/chirpstack-mqtt-forwarder-ap1 restart || true
    fi
  '"

fi

echo "[OK] Completed"
