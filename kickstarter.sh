#!/bin/bash
set -e

# Redirect output and errors to a log file
exec > >(tee -i /var/log/honeypot_setup.log)
exec 2>&1

# Define colors
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
BLUE=$(tput setaf 4)
YELLOW=$(tput setaf 3)
NC=$(tput sgr0) # No Color

# Function to print messages in color
print_in_color() {
    color=$1
    text=$2
    echo -e "\n${!color}${text}${NC}"
}

# Function to install a package
install_package() {
    apt-get install -y "$1" > /dev/null 2>&1; then
    if [[ $? -eq 0 ]]; then
        print_in_color "GREEN" "$1 installed successfully!"
    else
        print_in_color "RED" "Error installing $1."
        exit 1
    fi
}

# Function to add a cron job only if it doesn't exist
add_cron_job() {
    job="$1"
    if ! crontab -l 2>/dev/null | grep -Fq "$job"; then
        (crontab -l 2>/dev/null; echo "$job") | crontab -
        print_in_color "GREEN" "Cron job '$job' added."
    else
        print_in_color "YELLOW" "Cron job '$job' already exists."
    fi
}

# Ensure script is run as root
if [[ "$EUID" -ne 0 ]]; then
    print_in_color "RED" "You must run this script as root!"
    exit 1
fi

# Get the non-root user's home directory
USER_HOME=$(eval echo ~$SUDO_USER)

# Create all necessary directories if they don't exist
print_in_color "BLUE" "Checking and creating required directories..."
required_dirs=(
    "/var/log/honeypot/cowrie"
    "/var/log/honeypot/webhoneypot"
    "/var/lib/honeypot/dumps"
    "/var/backups/honeypot"
    "/opt/honeypot/scripts"
)

for dir in "${required_dirs[@]}"; do
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
        print_in_color "GREEN" "Directory $dir created."
    else
        print_in_color "YELLOW" "Directory $dir already exists."
    fi
done

# Set permissions and ownership
print_in_color "BLUE" "Setting permissions and ownership..."
chmod -R 700 /opt/honeypot/scripts
chown -R root:root /opt/honeypot/scripts

chmod -R 700 /var/backups/honeypot
chown -R root:root /var/backups/honeypot

# Update and install necessary packages
print_in_color "BLUE" "Updating repositories and installing necessary packages..."
apt-get update
necessary_tools=("git" "python3-pip" "tcpdump" "zip" "jq" "curl")
for tool in "${necessary_tools[@]}"; do
    install_package "$tool"
done

# Modify /etc/dshield.ini for additional logging
print_in_color "BLUE" "Modifying /etc/dshield.ini for additional logging..."
sed -i '/localcopy/d' /etc/dshield.ini
echo "localcopy=/var/log/honeypot/localdshield.log" >> /etc/dshield.ini

# Set up Cowrie log backups
print_in_color "BLUE" "Setting up Cowrie log backups..."
add_cron_job "0 0 * * * cp /srv/cowrie/var/log/cowrie/cowrie.json* /var/log/honeypot/cowrie/"

# Rotate web honeypot logs by date
print_in_color "BLUE" "Setting up log rotation for web honeypot logs..."
add_cron_job "0 0 * * * mv /srv/db/webhoneypot.json \"/var/log/honeypot/webhoneypot/webhoneypot_\$(date +\%Y\%m\%d).json\""

# Set up PCAP capture with tcpdump
print_in_color "BLUE" "Setting up PCAP capture with tcpdump..."
cat <<'EOT' > /var/lib/honeypot/dumps/grab_tcpdump.sh
#!/bin/bash
DEFAULT_IFACE=$(ip route | grep '^default' | awk '{print $5}')
tcpdump -i "$DEFAULT_IFACE" -s 65535 port not 12222 -w "/var/lib/honeypot/dumps/tcpdump_%Y-%m-%d_%H-%M-%S.pcap" -G 86400 -C 100 -Z root &
EOT
chmod +x /var/lib/honeypot/dumps/grab_tcpdump.sh

# Add cron job to start tcpdump at reboot
add_cron_job "@reboot /var/lib/honeypot/dumps/grab_tcpdump.sh"

# Backup honeypot data with password protection
print_in_color "BLUE" "Setting up data backups with password protection..."
cat <<'EOT' > /opt/honeypot/scripts/backup.sh
#!/bin/bash
TIMESTAMP=$(date "+%Y%m%d")
zip -r -e -P infected /var/backups/honeypot/home_$TIMESTAMP.zip /home
zip -r -e -P infected /var/backups/honeypot/logs_$TIMESTAMP.zip /var/log/honeypot
zip -r -e -P infected /var/backups/honeypot/srv_$TIMESTAMP.zip /srv
zip -r -e -P infected /var/backups/honeypot/dshield_logs_$TIMESTAMP.zip /var/log/dshield*
zip -r -e -P infected /var/backups/honeypot/crontabs_$TIMESTAMP.zip /var/spool/cron/crontabs
zip -r -e -P infected /var/backups/honeypot/dumps_$TIMESTAMP.zip /var/lib/honeypot/dumps

# Clear PCAP files older than 14 days to save space
find /var/lib/honeypot/dumps/ -name "*.pcap" -mtime +14 -exec rm {} \;

# Delete backups older than 14 days
find /var/backups/honeypot/ -name "*.zip" -mtime +14 -exec rm {} \;
EOT
chmod +x /opt/honeypot/scripts/backup.sh

# Add cron job for backup
add_cron_job "0 3 * * * /opt/honeypot/scripts/backup.sh"

# SCP Option
scp_enabled="no"
read -p "Do you want to set up SCP to transfer backups to a remote server? (y/n): " scp_choice
if [[ "$scp_choice" == "y" || "$scp_choice" == "Y" ]]; then
    scp_enabled="yes"
    read -p "Enter remote server IP or hostname: " remote_ip
    read -p "Enter remote user: " remote_user
    read -p "Enter the remote path for backups: " remote_path

    print_in_color "YELLOW" "Ensure SSH key-based authentication is set up between this server and the remote server."

    cat <<EOT > /opt/honeypot/scripts/scp_backup.sh
#!/bin/bash

LOGFILE="/var/log/honeypot/scp_backup.log"
TIMESTAMP=\$(date "+%Y-%m-%d %H:%M:%S")

scp -o ConnectTimeout=10 /var/backups/honeypot/* $remote_user@$remote_ip:$remote_path
if [[ \$? -ne 0 ]]; then
    echo "\$TIMESTAMP - Backup transfer failed!" >> \$LOGFILE
else
    echo "\$TIMESTAMP - Backup transfer successful!" >> \$LOGFILE
fi
EOT

    chmod +x /opt/honeypot/scripts/scp_backup.sh

    # Add cron job for SCP transfer
    add_cron_job "0 4 * * * /opt/honeypot/scripts/scp_backup.sh"

    print_in_color "GREEN" "SCP setup complete. Backup will be transferred daily at 4 AM."
else
    print_in_color "YELLOW" "SCP setup skipped. Backups will remain local."
fi

# Run the backup script and check status
print_in_color "BLUE" "Running the backup script and checking status..."
/opt/honeypot/scripts/backup.sh > /dev/null 2>&1
check_status "Backup"

# Notify of log locations
print_in_color "YELLOW" "Logs location: /var/log/honeypot"

# Prompt for additional tools installation
read -p "Do you want to install additional tools (cowrieprocessor, JSON-Log-Country)? (y/n): " install_tools
if [[ "$install_tools" == "y" || "$install_tools" == "Y" ]]; then

    # Change to the non-root user's home directory
    print_in_color "BLUE" "Switching to $USER_HOME for tool installations..."
    cd "$USER_HOME"

    # Install cowrieprocessor from GitHub
    print_in_color "BLUE" "Cloning cowrieprocessor into $USER_HOME..."
    sudo -u $SUDO_USER git clone https://github.com/jslagrew/cowrieprocessor.git

    if [[ $? -eq 0 ]]; then
        print_in_color "GREEN" "cowrieprocessor installed successfully in $USER_HOME/cowrieprocessor!"
    else
        print_in_color "RED" "Failed to install cowrieprocessor."
    fi

    # Install JSON-Log-Country from GitHub
    print_in_color "BLUE" "Cloning JSON-Log-Country into $USER_HOME..."
    sudo -u $SUDO_USER git clone https://github.com/justin-leibach/JSON-Log-Country.git

    if [[ $? -eq 0 ]]; then
        print_in_color "GREEN" "JSON-Log-Country installed successfully in $USER_HOME/JSON-Log-Country!"
    else
        print_in_color "RED" "Failed to install JSON-Log-Country."
    fi

else
    print_in_color "YELLOW" "Tool installation skipped."
fi

# Dynamic Final Message
if [[ "$scp_enabled" == "yes" ]]; then
    print_in_color "GREEN" "DShield KickStarter setup complete! PCAP logging, log rotation, backup, and SCP transfer configured."
else
    print_in_color "GREEN" "DShield KickStarter setup complete! PCAP logging, log rotation, and local backup configured."
fi
