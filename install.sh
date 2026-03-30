#!/bin/bash
set -e

# ===============================
# ThingsBoard Installation Script
# ===============================

# Global variables for credentials
THINGSBOARD_USER=""
THINGSBOARD_PASS=""

# Prompt user if a step fails
prompt_continue() {
    echo "An error occurred in the previous step."
    while true; do
        read -p "Do you want to (c)ontinue or (a)bort the installation? " choice
        case "$choice" in
            c|C ) echo "Continuing installation despite error."; break;;
            a|A )
                echo "Installation aborted."
                read -p "Do you want to rollback previous changes? (y/n): " rollback_choice
                if [[ "$rollback_choice" =~ ^[Yy]$ ]]; then
                    rollback_installation
                fi
                exit 1
                ;;
            * ) echo "Please answer c or a.";;
        esac
    done
}

# Rollback function
rollback_installation() {
    echo "Rolling back installation steps..."
    sudo service thingsboard stop 2>/dev/null
    if [ -f /usr/share/thingsboard/conf/thingsboard.conf.bak ]; then
        sudo mv /usr/share/thingsboard/conf/thingsboard.conf.bak /usr/share/thingsboard/conf/thingsboard.conf
        echo "Restored original Thingsboard configuration."
    fi
    sudo -u postgres psql -c "DROP DATABASE IF EXISTS thingsboard;"
    sudo -u postgres psql -c "DROP ROLE IF EXISTS ${THINGSBOARD_USER};"
    sudo dpkg -r thingsboard 2>/dev/null
    echo "Rollback completed."
}

# Step 0: Ask for credentials
echo "Step 0: Please provide Thingsboard credentials."
read -p "Enter Thingsboard username: " THINGSBOARD_USER
read -s -p "Enter Thingsboard password: " THINGSBOARD_PASS
echo ""

# Step 1: Install Java
echo "Step 1: Installing openjdk-17-jdk."
sudo apt update
if ! dpkg -s openjdk-17-jdk &>/dev/null; then
    sudo apt install -y openjdk-17-jdk
    [ $? -ne 0 ] && prompt_continue
else
    echo "Java already installed: $(java -version 2>&1 | head -n1)"
fi

# Step 2: Configure java alternatives
echo "Step 2: Configuring Java alternatives."
sudo update-alternatives --config java || prompt_continue

# Step 3: Install Thingsboard
echo "Step 3: Installing Thingsboard Service."
TB_VERSION="4.3.0.1"
wget https://github.com/thingsboard/thingsboard/releases/download/v${TB_VERSION}/thingsboard-${TB_VERSION}.deb
sudo dpkg -i thingsboard-${TB_VERSION}.deb || prompt_continue
echo "Thingsboard package installed successfully."

# Step 4: Configure Thingsboard Database
echo "Step 4: Configuring Thingsboard Database."
sudo -u postgres psql <<EOF
DO \$\$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${THINGSBOARD_USER}') THEN
       CREATE ROLE ${THINGSBOARD_USER} WITH LOGIN PASSWORD '${THINGSBOARD_PASS}';
   END IF;
END
\$\$;

CREATE DATABASE IF NOT EXISTS thingsboard WITH OWNER ${THINGSBOARD_USER};
EOF
echo "Database and role configured."

# Step 5: Update Thingsboard configuration
echo "Step 5: Updating Thingsboard configuration."
CONFIG_FILE="/usr/share/thingsboard/conf/thingsboard.conf"
[ -f "$CONFIG_FILE" ] && sudo cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"

# Ensure shell variables exist
: "${HTTP_BIND_ADDRESS:=0.0.0.0}"
: "${MQTT_BIND_ADDRESS:=127.0.0.1}"

sudo bash -c "cat >> $CONFIG_FILE" <<EOL

# DB Configuration 
export DATABASE_TS_TYPE=sql
export SPRING_DATASOURCE_URL=jdbc:postgresql://localhost:5432/thingsboard
export SPRING_DATASOURCE_USERNAME=${THINGSBOARD_USER}
export SPRING_DATASOURCE_PASSWORD=${THINGSBOARD_PASS}
export SQL_POSTGRES_TS_KV_PARTITIONING=MONTHS

# Bind addresses from shell variables
export HTTP_BIND_ADDRESS=${HTTP_BIND_ADDRESS}
export MQTT_BIND_ADDRESS=${MQTT_BIND_ADDRESS}

# Server ports
export HTTP_BIND_PORT=9090
export MQTT_BIND_PORT=1882
EOL

echo "Configuration file updated successfully."

# Step 6: Run Thingsboard installation script
echo "Step 6: Running Thingsboard installation script."
cd /usr/share/thingsboard/bin/install/
sudo ./install.sh || prompt_continue

# Step 7: Start Thingsboard service
echo "Step 7: Starting Thingsboard Service."
sudo systemctl daemon-reload
sudo service thingsboard start || prompt_continue

echo "Installation completed successfully!"
