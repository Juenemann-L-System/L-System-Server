#!/bin/bash
set -e

# ==========================================================
# Thingsboard + L-System Server Installation Script
# ==========================================================
# Features:
# - Vollständig automatisiert
# - Setzt Netzwerk-Bind-Adressen automatisch
# - Integrierte Rollback-Funktion
# - Einfache Wiederverwendbarkeit für künftige Systeme
# ==========================================================

# Global variables for credentials
THINGSBOARD_USER=""
THINGSBOARD_PASS=""

# Function: prompt the user if a step fails.
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

# Function: rollback previous steps
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

# Step 1: Install openjdk-17-jdk if needed
echo "Step 1: Installing openjdk-17-jdk."
sudo apt update
if ! dpkg -s openjdk-17-jdk &>/dev/null; then
    sudo apt install -y openjdk-17-jdk || prompt_continue
else
    JAVA_VERSION=$(java -version 2>&1 | head -n 1)
    echo "Java already installed: $JAVA_VERSION"
    if [[ "$JAVA_VERSION" != *"17"* ]]; then
         read -p "Detected Java version is not 17. Install openjdk-17-jdk? (y/n): " replace_choice
         if [[ "$replace_choice" =~ ^[Yy]$ ]]; then
             sudo apt install -y openjdk-17-jdk || prompt_continue
         else
             echo "Continuing with existing Java version."
         fi
    fi
fi

# Step 2: Configure java alternatives
echo "Step 2: Configuring Java alternatives."
sudo update-alternatives --config java || prompt_continue

# Step 3: Install Thingsboard package
echo "Step 3: Installing Thingsboard Service."
TB_VERSION="4.3.0.1"
wget https://github.com/thingsboard/thingsboard/releases/download/v${TB_VERSION}/thingsboard-${TB_VERSION}.deb || prompt_continue
sudo dpkg -i thingsboard-${TB_VERSION}.deb || prompt_continue

# Step 4: Configure Thingsboard Database
echo "Step 4: Configuring Thingsboard Database."
sudo -u postgres psql <<EOF || prompt_continue
CREATE ROLE ${THINGSBOARD_USER} WITH LOGIN PASSWORD '${THINGSBOARD_PASS}';
CREATE DATABASE thingsboard WITH OWNER ${THINGSBOARD_USER};
EOF

# Step 5: Update Thingsboard configuration file
echo "Step 5: Updating Thingsboard configuration."
CONFIG_FILE="/usr/share/thingsboard/conf/thingsboard.conf"
if [ -f "$CONFIG_FILE" ]; then
    sudo cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
    echo "Backup saved as ${CONFIG_FILE}.bak."
fi

sudo bash -c "cat >> $CONFIG_FILE" <<EOL

# DB Configuration 
export DATABASE_TS_TYPE=sql
export SPRING_DATASOURCE_URL=jdbc:postgresql://localhost:5432/thingsboard
export SPRING_DATASOURCE_USERNAME=${THINGSBOARD_USER}
export SPRING_DATASOURCE_PASSWORD=${THINGSBOARD_PASS}
export SQL_POSTGRES_TS_KV_PARTITIONING=MONTHS

# NETWORK CONFIGURATION FOR ALL INSTALLATIONS
export HTTP_BIND_ADDRESS=0.0.0.0
export MQTT_BIND_ADDRESS=127.0.0.1

# Server Port Configuration
export HTTP_BIND_PORT=9090
export MQTT_BIND_PORT=1882
EOL

# Step 6: Run Thingsboard installation script
echo "Step 6: Running Thingsboard installation script."
cd /usr/share/thingsboard/bin/install/
sudo ./install.sh || prompt_continue

# Step 7: Start Thingsboard service
echo "Step 7: Starting Thingsboard Service."
sudo service thingsboard start || prompt_continue

echo "Installation completed successfully!"
