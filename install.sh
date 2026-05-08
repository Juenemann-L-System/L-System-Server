#!/bin/bash
set -e

# Recommendations:
# 1. Always test this script in a safe environment (e.g. a VM or container) before using it in production.
# 2. Consider logging output for auditing.
# 3. Ensure you have backups of any important data before running a rollback.
# 4. Be aware that some rollback actions (e.g. removing Java) might affect other applications.

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

# Function: rollback previous steps (this is a basic implementation)
rollback_installation() {
    echo "Rolling back installation steps..."

    # Stop Thingsboard service if running
    sudo systemctl stop thingsboard 2>/dev/null || true

    # Restore Thingsboard configuration if a backup exists.
    if [ -f /etc/thingsboard/conf/thingsboard.conf.bak ]; then
        sudo mv /etc/thingsboard/conf/thingsboard.conf.bak /etc/thingsboard/conf/thingsboard.conf
        echo "Restored original Thingsboard configuration."
    fi

    # Drop Thingsboard database and role.
    sudo -u postgres psql -c "DROP DATABASE IF EXISTS thingsboard;"
    sudo -u postgres psql -c "DROP ROLE IF EXISTS ${THINGSBOARD_USER};"

    # Remove Thingsboard package.
    sudo dpkg -r thingsboard 2>/dev/null || true

    echo "Rollback completed."
}

# Step 0: Ask for credentials
echo "Step 0: Please provide Thingsboard credentials."
read -p "Enter Thingsboard username: " THINGSBOARD_USER
read -s -p "Enter Thingsboard password: " THINGSBOARD_PASS
echo ""

# Step 1: Install dependencies
echo "Step 1: Installing required packages."

sudo apt update

sudo apt install -y curl wget
if [ $? -ne 0 ]; then
    prompt_continue
fi

# Step 2: Install openjdk-17-jdk if needed
echo "Step 2: Installing openjdk-17-jdk."

if ! dpkg -s openjdk-17-jdk &>/dev/null; then
    sudo apt install -y openjdk-17-jdk
    if [ $? -ne 0 ]; then
        prompt_continue
    else
        echo "openjdk-17-jdk installed successfully."
    fi
else
    JAVA_VERSION=$(java -version 2>&1 | head -n 1)
    echo "Java already installed: $JAVA_VERSION"

    if [[ "$JAVA_VERSION" != *"17"* ]]; then
        read -p "Detected Java version is not 17. Install openjdk-17-jdk? (y/n): " replace_choice

        if [[ "$replace_choice" =~ ^[Yy]$ ]]; then
            sudo apt install -y openjdk-17-jdk

            if [ $? -ne 0 ]; then
                prompt_continue
            fi
        else
            echo "Continuing with the existing Java version."
        fi
    fi
fi

# Step 3: Configure java alternatives
echo "Step 3: Configuring Java alternatives."

sudo update-alternatives --config java

if [ $? -ne 0 ]; then
    prompt_continue
else
    echo "Java alternatives configured."
fi

# Step 4: Fetch latest ThingsBoard version
echo "Step 4: Fetching latest ThingsBoard version."

LATEST_VERSION=$(curl -s https://api.github.com/repos/thingsboard/thingsboard/releases/latest | grep '"tag_name"' | cut -d '"' -f4 | sed 's/v//')

if [ -z "$LATEST_VERSION" ]; then
    echo "Could not fetch latest ThingsBoard version."
    exit 1
fi

echo "Latest ThingsBoard version detected: $LATEST_VERSION"

# Step 5: Download latest ThingsBoard package
echo "Step 5: Downloading latest ThingsBoard package."

wget https://github.com/thingsboard/thingsboard/releases/download/v${LATEST_VERSION}/thingsboard-${LATEST_VERSION}.deb

if [ $? -ne 0 ]; then
    prompt_continue
fi

# Step 6: Install ThingsBoard package
echo "Step 6: Installing ThingsBoard package."

sudo dpkg -i thingsboard-${LATEST_VERSION}.deb

if [ $? -ne 0 ]; then
    prompt_continue
else
    echo "ThingsBoard package installed successfully."
fi

sudo systemctl daemon-reload

# Step 7: Configure PostgreSQL database
echo "Step 7: Configuring PostgreSQL database."

sudo systemctl start postgresql

sudo -u postgres psql <<EOF
CREATE ROLE ${THINGSBOARD_USER} WITH LOGIN PASSWORD '${THINGSBOARD_PASS}';
CREATE DATABASE thingsboard WITH OWNER ${THINGSBOARD_USER};
EOF

if [ $? -ne 0 ]; then
    prompt_continue
else
    echo "Database and role created successfully."
fi

# Step 8: Update ThingsBoard configuration
echo "Step 8: Updating ThingsBoard configuration."

CONFIG_FILE="/etc/thingsboard/conf/thingsboard.conf"

if [ -f "$CONFIG_FILE" ]; then
    sudo cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
    echo "Backup of configuration file saved as ${CONFIG_FILE}.bak."
fi

sudo bash -c "cat >> $CONFIG_FILE" <<EOL

# DB Configuration
export DATABASE_TS_TYPE=sql
export SPRING_DATASOURCE_URL=jdbc:postgresql://localhost:5432/thingsboard
export SPRING_DATASOURCE_USERNAME=${THINGSBOARD_USER}
export SPRING_DATASOURCE_PASSWORD=${THINGSBOARD_PASS}
export SQL_POSTGRES_TS_KV_PARTITIONING=MONTHS

# Server Port Configuration
export HTTP_BIND_PORT=9090
export MQTT_BIND_PORT=1882
EOL

if [ $? -ne 0 ]; then
    prompt_continue
else
    echo "Configuration file updated successfully."
fi

# Step 9: Run ThingsBoard installation script
echo "Step 9: Running ThingsBoard installation script."

cd /usr/share/thingsboard/bin/install/

sudo ./install.sh

if [ $? -ne 0 ]; then
    prompt_continue
else
    echo "Installation script executed successfully."
fi

# Step 10: Start ThingsBoard service
echo "Step 10: Starting ThingsBoard service."

sudo systemctl enable thingsboard
sudo systemctl restart thingsboard

if [ $? -ne 0 ]; then
    prompt_continue
else
    echo "ThingsBoard service started successfully."
fi

# Step 11: Show service status
echo "Step 11: Checking service status."

sudo systemctl status thingsboard --no-pager

echo ""
echo "Installation completed successfully!"
echo "Installed ThingsBoard version: $LATEST_VERSION"
