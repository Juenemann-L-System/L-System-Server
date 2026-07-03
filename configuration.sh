#!/usr/bin/env bash
set -euo pipefail

########################################
# CONFIG INPUT
########################################

read -rp "Gateway IP Address: " GW_IP
read -rp "Gateway USER: " GW_USER
read -rsp "Gateway Password: " GW_PASS
echo ""

read -rp "MQTT Server IP: " MQTT_IP
read -rp "MQTT Server Port (1883): " MQTT_PORT
echo ""

read -rp "Install (i) or Update config only (u): " MODE

########################################
# SSH helpers (NO MULTIPLE PASSWORD PROMPTS)
########################################

SSH="sshpass -p \"$GW_PASS\" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
SCP="sshpass -p \"$GW_PASS\" scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

echo "[INFO] Checking gateway SSH..."
$SSH ${GW_USER}@${GW_IP} "echo ok" >/dev/null
echo "[OK] Gateway reachable"

########################################
# Detect gateway architecture
########################################

ARCH=$($SSH ${GW_USER}@${GW_IP} "uname -m" | tr -d '\r')

echo "[INFO] Gateway arch: $ARCH"

########################################
# Select correct IPK (FIXED FOR MTCAP)
########################################

# IMPORTANT: your gateway is MTCAP => arm926ejste
IPK_URL="https://artifacts.chirpstack.io/downloads/chirpstack-mqtt-forwarder/vendor/multitech/conduit_ap/chirpstack-mqtt-forwarder_4.5.1-r1_arm926ejste.ipk"

IPK_FILE="chirpstack-mqtt-forwarder.ipk"

########################################
# INSTALL MODE
########################################

if [[ "$MODE" == "i" ]]; then

  echo "[INFO] Downloading IPK on server..."
  curl -L "$IPK_URL" -o "/tmp/$IPK_FILE"

  echo "[INFO] Copying IPK to gateway..."
  $SCP "/tmp/$IPK_FILE" ${GW_USER}@${GW_IP}:/tmp/

  echo "[INFO] Installing on gateway..."

  $SSH ${GW_USER}@${GW_IP} "echo '$GW_PASS' | sudo -S sh -c '
    set -e

    echo \"[GATEWAY] Installing package...\"

    if command -v opkg >/dev/null 2>&1; then
      opkg install /tmp/$IPK_FILE || true
    fi

    echo \"[GATEWAY] Detecting config path...\"

    CFG=\"\"
    if [ -f /var/config/chirpstack-mqtt-forwarder/ap1/chirpstack-mqtt-forwarder.toml ]; then
      CFG=/var/config/chirpstack-mqtt-forwarder/ap1/chirpstack-mqtt-forwarder.toml
    fi

    if [ -z \"\$CFG\" ]; then
      echo \"[ERROR] Config not found\"
      exit 1
    fi

    echo \"[GATEWAY] Updating MQTT config\"

    sed -i \"s#server=.*#server=\\\"tcp://${MQTT_IP}:${MQTT_PORT}\\\"#\" \$CFG || true

    echo \"[GATEWAY] Enabling services...\"

    if [ -x /etc/init.d/lora-network-server ]; then
      /etc/init.d/lora-network-server restart || true
    fi

  '"

fi
########################################
# UPDATE MODE
########################################

if [[ "$MODE" == "u" ]]; then

  echo "[INFO] Updating config only..."

  $SSH ${GW_USER}@${GW_IP} "echo '$GW_PASS' | sudo -S sh -c '
    CFG=/var/config/chirpstack-mqtt-forwarder/ap1/chirpstack-mqtt-forwarder.toml

    if [ -f \$CFG ]; then
      sed -i \"s#server=.*#server=\\\"tcp://${MQTT_IP}:${MQTT_PORT}\\\"#\" \$CFG
      echo \"[GATEWAY] Config updated\"
    else
      echo \"[WARN] Config not found\"
    fi
  '"

fi

########################################
# MONIT SETUP (MTCAP FIX)
########################################

echo "[INFO] Setting up monit (if available)..."

$SSH ${GW_USER}@${GW_IP} "echo '$GW_PASS' | sudo -S sh -c '
  if [ -f /var/config/chirpstack-mqtt-forwarder/ap1/examples/chirpstack-mqtt-forwarder-ap1.monit ]; then

    cp /var/config/chirpstack-mqtt-forwarder/ap1/examples/chirpstack-mqtt-forwarder-ap1.monit /etc/monit.d/ 2>/dev/null || true

    if command -v monit >/dev/null 2>&1; then
      monit reload || true
      monit restart chirpstack-mqtt-forwarder-ap1 || true
    fi

  else
    echo \"[WARN] Monit config not found\"
  fi
'"

########################################
# FINAL CHECK
########################################

echo "[INFO] Verifying process..."

$SSH ${GW_USER}@${GW_IP} "ps | grep chirpstack || true"

echo "[OK] Completed"
