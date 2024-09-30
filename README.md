# DShieldKickStarter

This project automates the backup of honeypot data, including SCP transfers to a remote server and local logging of backup operations. The script ensures regular backups of logs and other relevant files, with the option to transfer those backups to a remote server using SCP. It also maintains a log of the backup success or failure for auditing purposes. Optional tools have also been added for convenience. Blog write-up https://www.iamjoshgilman.com/kickstart-your-dshield-honeypot/

## Features
- **Automated Backup**: Backups are created and password-protected to prevent accidental execution.
- **Optional SCP Transfer**: The script offers the option to transfer backups to a remote server via SCP, using key-based authentication.
- **Logging**: Logs the success or failure of SCP transfers to a local file.
- **PCAP File Management**: Clears older PCAP files to save space and ensure smooth operation.
- **Cron Jobs**: Automates the backup and log rotation processes.
- **Additional Tools**: Optional install of helpful log processing tools (cowrieprocessor, JSON-Log-Country)
- **Key-based Authentication**: If using SCP, ensure SSH key-based authentication is set up between the honeypot and remote server.

### Required Tools
The script will install the following packages if they are not already installed:
- `git`
- `python3-pip`
- `tcpdump`
- `zip`
- `jq`
- `curl`

## Installation

### Clone the Repository

```bash
git clone https://github.com/iamjoshgilman/DShieldKickStarter.git
cd DShieldKickStarter
```

### Set Executable Permissions
Ensure the main script has executable permissions:

```bash
chmod +x kickstarter.sh
```

### Run the Script
To start the backup setup, run the following command:

```bash
sudo ./kickstarter.sh
```

## Usage

### SCP Transfer
During the setup process, you will be prompted to enable SCP transfers. If enabled, you will need to provide the following details:
- Remote server IP or hostname
- Remote username
- Remote path to store backups

The script assumes that key-based authentication is already configured between the honeypot server and the remote server. 

### Logging
The script logs the status of the backup and SCP transfer operations to a file located at:

```bash
/var/log/honeypot/scp_backup.log
```

This file contains timestamps and success or failure messages for each backup attempt. The log is appended with each run, preserving a history of the operations.

### Cron Jobs
The script automatically sets up cron jobs for:
- **Daily Backups**: The backup script is scheduled to run daily at 3:00 AM.
- **Log Rotation**: Will archive and rotate the logs monthly.
- **SCP Transfer (if enabled)**: If SCP is enabled, it is scheduled to transfer backups at 4:00 AM daily.

## File Structure
The main files included in this project are:
- `honeypot_backup.sh`: The script handles the setup, backups, and optional SCP transfers.
- `scp_backup.sh`: Automatically generated script for SCP transfer if enabled.
- `backup.sh`: Handles the log and home directory data backup process.

### Directory Structure
The script creates the following directories if they do not exist:
- `/var/log/honeypot/cowrie`: Stores Cowrie honeypot logs.
- `/var/log/honeypot/webhoneypot`: Stores web honeypot logs.
- `/var/lib/honeypot/dumps`: Stores packet capture files (PCAP).
- `/var/backups/honeypot`: Stores zipped backup files.
- `/opt/honeypot/scripts`: Stores custom scripts for backups and transfers.

## Customization

### Modify Backup Content
To modify what gets backed up, you can edit the backup script located at:
```bash
/opt/honeypot/scripts/backup.sh
```
You can adjust which directories or files are zipped and password-protected.
The default password for the ZIP files is **infected**

## Additional Tools
Optionally, Cowrieprocessor, and JSON-Log-Country can be cloned in your home directory. Additional Information
can be found at their respective repos. 

- `https://github.com/jslagrew/cowrieprocessor`
- `https://github.com/justin-leibach/JSON-Log-Country`
