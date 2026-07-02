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

if [[ "$MODE" != "i" && "$MODE" != "u" ]]; then
  echo "Invalid option"
  exit 1
fi

IPK_FILE="chirpstack-mqtt-forwarder.ipk"
IPK_URL="https://artifacts.chirpstack.io/downloads/chirpstack-mqtt-forwarder/vendor/multitech/conduit_ap3/chirpstack-mqtt-forwarder_4.3.1-r1_mtcap3.ipk"

########################################
# CHECK SSH
########################################

echo "[INFO] Checking gateway SSH..."

sshpass -p "$GW_PASS" ssh -o StrictHostKeyChecking=no -tt "$GW_USER@$GW_IP" "echo ok" >/dev/null

echo "[OK] Gateway reachable"

########################################
# INSTALL MODE
########################################

if [[ "$MODE" == "i" ]]; then
  echo "[INFO] Downloading package..."

  curl -L "$IPK_URL" -o "$IPK_FILE"

  echo "[INFO] Uploading package to gateway..."

  sshpass -p "$GW_PASS" scp -o StrictHostKeyChecking=no "$IPK_FILE" "$GW_USER@$GW_IP:/tmp/"

  echo "[INFO] Installing on gateway..."

  sshpass -p "$GW_PASS" ssh -tt "$GW_USER@$GW_IP" bash -s <<EOF

echo "$GW_PASS" | sudo -S sh -c '
echo "[GATEWAY] Installing package..."
opkg install /tmp/$IPK_FILE || true

echo "[GATEWAY] Updating MQTT config..."
CFG="/var/config/chirpstack-mqtt-forwarder/chirpstack-mqtt-forwarder.toml"

if [ -f "\$CFG" ]; then
  sed -i "s#server=.*#server=\"tcp://$MQTT_IP:$MQTT_PORT\"#" "\$CFG"
fi

echo "[GATEWAY] Restarting services..."
/etc/init.d/lora-network-server restart || true
/etc/init.d/chirpstack-mqtt-forwarder-ap1 restart || true
'
EOF

########################################
# UPDATE MODE
########################################

else
  echo "[INFO] Updating config only..."

  sshpass -p "$GW_PASS" ssh -tt "$GW_USER@$GW_IP" bash -s <<EOF

echo "$GW_PASS" | sudo -S sh -c '
CFG="/var/config/chirpstack-mqtt-forwarder/chirpstack-mqtt-forwarder.toml"

if [ -f "\$CFG" ]; then
  sed -i "s#server=.*#server=\"tcp://$MQTT_IP:$MQTT_PORT\"#" "\$CFG"
fi

/etc/init.d/chirpstack-mqtt-forwarder-ap1 restart || true
'
EOF

fi

echo "[OK] Completed"
