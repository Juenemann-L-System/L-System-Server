
#!/bin/bash
set -Eeuo pipefail

# ============================================================
# Armatherm ThingsBoard Installation / Upgrade
# Ubuntu 24.04 - ThingsBoard CE - Java 25 - PostgreSQL
# ============================================================

THINGSBOARD_USER=""
THINGSBOARD_PASS=""
LATEST_VERSION=""
CONFIG_FILE="/etc/thingsboard/conf/thingsboard.conf"

# ------------------------------------------------------------
# Fehlerbehandlung
# ------------------------------------------------------------

trap 'echo "FEHLER in Zeile $LINENO. Installation abgebrochen."' ERR

# ------------------------------------------------------------
# Step 0: Zugangsdaten
# ------------------------------------------------------------

echo "Step 0: Please provide ThingsBoard credentials."

read -r -p "Enter ThingsBoard username: " THINGSBOARD_USER
read -r -s -p "Enter ThingsBoard password: " THINGSBOARD_PASS
echo ""

if [[ ! "$THINGSBOARD_USER" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
    echo "ERROR: Invalid PostgreSQL username."
    exit 1
fi

# ------------------------------------------------------------
# Step 1: Required packages
# ------------------------------------------------------------

echo "Step 1: Installing required packages."

sudo apt update
sudo apt install -y curl wget python3

# ------------------------------------------------------------
# Step 2: Java 25
# ------------------------------------------------------------

echo "Step 2: Checking Java 25."

sudo apt install -y openjdk-25-jdk-headless

JAVA_PATH="/usr/lib/jvm/java-25-openjdk-$(dpkg --print-architecture)/bin/java"

if [ -x "$JAVA_PATH" ]; then
    sudo update-alternatives --set java "$JAVA_PATH"
fi

JAVA_VERSION=$(java -version 2>&1 | head -n 1)

echo "Detected Java: $JAVA_VERSION"

if [[ "$JAVA_VERSION" != *"25"* ]]; then
    echo "ERROR: Java 25 is not active."
    exit 1
fi

echo "Java 25 is active."

# ------------------------------------------------------------
# Step 3: Detect latest ThingsBoard version
# ------------------------------------------------------------

echo "Step 3: Detecting latest ThingsBoard version."

LATEST_VERSION=$(
    curl -fsSL https://api.github.com/repos/thingsboard/thingsboard/releases/latest |
    python3 -c 'import sys,json; print(json.load(sys.stdin)["tag_name"].lstrip("v"))'
)

if [[ -z "$LATEST_VERSION" ]]; then
    echo "ERROR: ThingsBoard version could not be detected."
    exit 1
fi

echo "Latest ThingsBoard version detected: $LATEST_VERSION"

# ------------------------------------------------------------
# Step 4: Download ThingsBoard package
# ------------------------------------------------------------

echo "Step 4: Downloading ThingsBoard package."

PACKAGE="thingsboard-${LATEST_VERSION}.deb"

wget -O "$PACKAGE" \
"https://github.com/thingsboard/thingsboard/releases/download/v${LATEST_VERSION}/${PACKAGE}"

# ------------------------------------------------------------
# Step 5: Backup existing database and configuration
# ------------------------------------------------------------

echo "Step 5: Creating backups."

sudo mkdir -p /var/backups/thingsboard

if sudo -u postgres psql -tAc \
"SELECT 1 FROM pg_database WHERE datname='thingsboard'" |
grep -q 1; then

    BACKUP_FILE="/var/backups/thingsboard/thingsboard_$(date +%Y%m%d_%H%M%S).dump"

    sudo -u postgres pg_dump -Fc thingsboard |
    sudo tee "$BACKUP_FILE" >/dev/null

    echo "Database backup created: $BACKUP_FILE"
else
    echo "No existing ThingsBoard database found."
fi

if sudo test -f "$CONFIG_FILE"; then
    sudo cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
    echo "Configuration backup created."
fi

# ------------------------------------------------------------
# Step 6: Install ThingsBoard package
# ------------------------------------------------------------

echo "Step 6: Installing ThingsBoard package."

sudo systemctl stop thingsboard 2>/dev/null || true

sudo dpkg -i "$PACKAGE" || {
    sudo apt-get install -f -y
    sudo dpkg -i "$PACKAGE"
}

echo "ThingsBoard package installed successfully."

# ------------------------------------------------------------
# Step 7: Configure PostgreSQL
# ------------------------------------------------------------

echo "Step 7: Configuring PostgreSQL database."

sudo systemctl enable postgresql
sudo systemctl start postgresql

# Escape single quotes in the password for SQL.
SQL_PASSWORD=${THINGSBOARD_PASS//\'/\'\'}

# Create role if absent; otherwise update its password.
sudo -u postgres psql -v ON_ERROR_STOP=1 \
    -c "DO \$\$ BEGIN
        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='${THINGSBOARD_USER}') THEN
            CREATE ROLE ${THINGSBOARD_USER} WITH LOGIN PASSWORD '${SQL_PASSWORD}';
        ELSE
            ALTER ROLE ${THINGSBOARD_USER} WITH LOGIN PASSWORD '${SQL_PASSWORD}';
        END IF;
    END \$\$;"

# Create database only if it does not exist.
if ! sudo -u postgres psql -tAc \
"SELECT 1 FROM pg_database WHERE datname='thingsboard'" |
grep -q 1; then

    sudo -u postgres createdb \
        -O "$THINGSBOARD_USER" thingsboard

    echo "ThingsBoard database created."
else
    echo "Existing ThingsBoard database preserved."
fi

# ------------------------------------------------------------
# Step 8: Configure ThingsBoard
# ------------------------------------------------------------

echo "Step 8: Updating ThingsBoard configuration."

sudo touch "$CONFIG_FILE"

# Remove previous Armatherm configuration block.
sudo sed -i \
'/# BEGIN ARMATHERM THINGSBOARD CONFIG/,/# END ARMATHERM THINGSBOARD CONFIG/d' \
"$CONFIG_FILE"

sudo tee -a "$CONFIG_FILE" >/dev/null <<EOF

# BEGIN ARMATHERM THINGSBOARD CONFIG

# DB Configuration
export DATABASE_TS_TYPE=sql
export SPRING_DATASOURCE_URL=jdbc:postgresql://localhost:5432/thingsboard
export SPRING_DATASOURCE_USERNAME=${THINGSBOARD_USER}
export SPRING_DATASOURCE_PASSWORD='${THINGSBOARD_PASS}'
export SQL_POSTGRES_TS_KV_PARTITIONING=MONTHS

# Server Port Configuration
export HTTP_BIND_PORT=9090
export MQTT_BIND_PORT=1882

# END ARMATHERM THINGSBOARD CONFIG
EOF

sudo chmod 600 "$CONFIG_FILE"

echo "ThingsBoard configuration updated."

# ------------------------------------------------------------
# Step 9: Initialize / Upgrade database schema
# ------------------------------------------------------------

echo "Step 9: Running ThingsBoard installation script."

sudo /usr/share/thingsboard/bin/install/install.sh

echo "ThingsBoard database initialization completed."

# ------------------------------------------------------------
# Step 10: Start ThingsBoard service
# ------------------------------------------------------------

echo "Step 10: Starting ThingsBoard service."

sudo systemctl daemon-reload
sudo systemctl enable thingsboard
sudo systemctl restart thingsboard

# ------------------------------------------------------------
# Step 11: Check service status
# ------------------------------------------------------------

echo "Step 11: Checking ThingsBoard service."

sleep 5

sudo systemctl status thingsboard --no-pager

echo ""
echo "============================================================"
echo "ThingsBoard installation / upgrade completed."
echo "Installed version: $LATEST_VERSION"
echo "Web interface: http://192.168.2.10:9090"
echo "============================================================"
