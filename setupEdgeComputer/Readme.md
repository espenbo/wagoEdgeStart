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
- Install EKBPRO KNX Terminal and set up a KNX project (`install_knx_terminal.sh`)
- Run all tasks sequentially

#### Usage

1. Make the script executable:
   ```sh
   chmod +x setup_edge_computer.sh


2. Run the script with root privileges:

   ```sh
    sudo ./setup_edge_computer.sh


3. Follow the on-screen menu to select and execute the desired tasks.

### install_knx_terminal.sh

This script installs [EKBPRO KNX Terminal Python](https://github.com/espenbo/ekbpro-knx-terminal-python). It is started from option 18 in `setup_edge_computer.sh`, or on its own as a normal user with sudo rights:

```sh
./install_knx_terminal.sh
```

The script installs the program, asks for the KNX project from ETS (upload from your PC, a path on the machine or a URL), asks how the machine is connected to KNX, sets up the floor plan, and starts the server as a systemd service.

The floor plan is made by `knx_plan_wizard.py`, one floor at a time. It reads the rooms from a PNG or JPG drawing, or you type them row by row. A drawing needs clean, dark walls on a light background, and you enter the outer width of the building in metres. Rooms are rectangles, so an L-shaped room becomes its bounding box. The result is shown in the terminal, where rooms can be deleted or merged and linked to rooms in ETS.

### reset_setupedge.sh

This script is used to reset and remove all changes made by the setup_edge_computer.sh script. It provides a menu-driven interface for easy navigation and selection of reset tasks.

#### Features

- List system updates
- Uninstall Tailscale
- Reset UFW firewall settings
- Uninstall Cockpit web manager
- Uninstall Docker and Docker Compose
- Uninstall Samba and domain functionality
- Uninstall other necessary programs
- Remove WAGO login script
- Leave and reset Samba domain
- Uninstall OPC UA Commander
- Uninstall Node.js
- Uninstall Node-RED
- Uninstall unattended-upgrades
- Run all reset tasks sequentially

#### Usage

1. Make the script executable:

   ```sh
    chmod +x reset_setupedge.sh


2. Run the script with root privileges:

   ```sh
    sudo ./reset_setupedge.sh


3. Follow the on-screen menu to select and execute the desired reset tasks.


Contributions are welcome! Please fork the repository and submit a pull request.

Use these scripts at your own risk. Ensure you have backups of any important data before running these scripts.
