README.md

# Edge Computer Setup and Reset Scripts

## Overview

This repository contains two shell scripts designed for setting up and resetting an edge computer. The `setup_edge_computer.sh` script is used to install and configure various software and services on the computer, while the `reset_setupedge.sh` script is used to remove and reset all the changes made by the setup script.

## Scripts

### setup_edge_computer.sh

This script is used to set up the edge computer by installing and configuring necessary software and services. It provides a menu-driven interface for easy navigation and selection of tasks.

#### Features

- Update package list and upgrade system
- Install and configure Tailscale
- Install and configure UFW firewall manager
- Install Cockpit web manager
- Install Docker and Docker Compose
- Install LazyDocker (CLI Docker manager)
- Install OPC UA Commander
- Install Node-RED
- Install Samba and join domain
- Install Node.js
- Install other necessary programs
- Install unattended-upgrades
- Run all tasks sequentially

#### Usage

1. Make the script executable:
   ```sh
   chmod +x setup_edge_computer.sh

    Run the script with root privileges:

    sh

    sudo ./setup_edge_computer.sh

    Follow the on-screen menu to select and execute the desired tasks.

### reset_setupedge.sh

This script is used to reset and remove all changes made by the setup_edge_computer.sh script. It provides a menu-driven interface for easy navigation and selection of reset tasks.

#### Features

    List system updates
    Uninstall Tailscale
    Reset UFW firewall settings
    Uninstall Cockpit web manager
    Uninstall Docker and Docker Compose
    Uninstall Samba and domain functionality
    Uninstall other necessary programs
    Remove WAGO login script
    Leave and reset Samba domain
    Uninstall OPC UA Commander
    Uninstall Node.js
    Uninstall Node-RED
    Uninstall unattended-upgrades
    Run all reset tasks sequentially

#### Usage

    Make the script executable:

    sh

chmod +x reset_setupedge.sh

Run the script with root privileges:

sh

    sudo ./reset_setupedge.sh

    Follow the on-screen menu to select and execute the desired reset tasks.


Contributions are welcome! Please fork the repository and submit a pull request.

Use these scripts at your own risk. Ensure you have backups of any important data before running these scripts.



### Instructions for Uploading the Scripts

1. Create a new GitHub repository.
2. Upload the `setup_edge_computer.sh` and `reset_setupedge.sh` scripts to the repository.
3. Add the `README.md` file with the above content to the repository.
4. Commit and push the changes to GitHub.

If you need further assistance with any steps, feel free to ask!
