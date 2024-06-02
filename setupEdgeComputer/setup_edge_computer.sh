#!/bin/bash

# Initialize service status variables
COCKPIT_ACTIVE="inactive"
PORTAINER_ACTIVE="inactive"
ISSUE_FILE_COCKPIT="/etc/issue.d/cockpit.issue"  # Ensure this path is correct

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    echo "or with sudo"
    exit 1
fi

# Function to display all tasks in a table format
show_menu(){
    normal=`echo "\033[m"`
    menu=`echo "\033[36m"` #blue
    number=`echo "\033[33m"` #yellow
    bgred=`echo "\033[41m"`
    fgred=`echo "\033[31m"`
    printf "\n${menu}********* System Provisioning Tool ***********${normal}\n"
    printf "${menu} ${number} 1)${menu} Run 'apt update' and 'apt upgrade -y' ${normal}\n"
    printf "${menu} ${number} 2)${menu} Install WAGO login script ${normal}\n"
    printf "${menu} ${number} 3)${menu} Install UFW firewall manager and open specific ports ${normal}\n"
    printf "${menu} ${number} 4)${menu} Install Tailscale ${normal}\n"
    printf "${menu} ${number} 5)${menu} Install Cockpit web manager ${normal}\n"
    printf "${menu} ${number} 6)${menu} Install Docker and Docker Compose ${normal}\n"
    printf "${menu} ${number} 7)${menu} Install LazyDocker. CLI docker manager. https://github.com/jesseduffield/lazydocker ${normal}\n"
    printf "${menu} ${number} 8)${menu} Install OPC UA Commander ${normal}\n"
    printf "${menu} ${number} 9)${menu} Install Node-RED ${normal}\n"
    printf "${menu} ${number} 10)${menu} Install Samba and domain functionality ${normal}\n"
    printf "${menu} ${number} 11)${menu} Install Node.js ${normal}\n"
    printf "${menu} ${number} 12)${menu} Install other necessary programs ${normal}\n"
    printf "${menu} ${number} 13)${menu} Setup Samba and join domain ${normal}\n"
    printf "${menu} ${number} 14)${menu} Run all tasks sequentially ${normal}\n"
    printf "${menu} ${number} 15)${menu} Install unattended-upgrades ${normal}\n"
    printf "${menu} ${number} 16)${menu} show menu ${normal}\n"
    printf "${menu} ${number} x)${menu} Exit ${normal}\n"
    printf "Please enter a menu option and enter or ${fgred}x to exit. ${normal}"
    read opt
}

option_picked(){
    msgcolor=`echo "\033[01;31m"` # bold red
    normal=`echo "\033[00;00m"` # normal white
    message=${@:-"${normal}Error: No message passed"}
    printf "${msgcolor}${message}${normal}\n"
}

# Update package list and upgrade system
update_system() {
  echo "Updating the system..."
  apt update
  apt upgrade -y
}

# Install Tailscale
install_tailscale() {
  echo "Installing Tailscale..."
  curl -fsSL https://tailscale.com/install.sh | sh
  tailscale up
}

# Install UFW and set it up
install_ufw() {
  if ! command -v ufw &> /dev/null; then
      echo "UFW is not installed. Installing UFW..."
      apt-get install -y ufw
  fi
  echo "Resetting UFW to default settings..."
  ufw reset
  echo "Setting default policies to deny incoming and allow outgoing..."
  ufw default deny incoming
  ufw default allow outgoing
  echo "Allowing SSH on port 22..."
  ufw allow 22/tcp
  echo "Allowing HTTP on port 80..."
  ufw allow 80/tcp
  echo "Allowing HTTPS on port 443..."
  ufw allow 443/tcp
  echo "Allowing Modbus on port 502..."
  ufw allow 502/tcp
  echo "Allowing OPC/UA Discovery Server on ports 4840 and 4843..."
  ufw allow 4840/tcp
  ufw allow 4843/tcp
  echo "Allowing OPC/UA Reference Server on ports 62540 and 62541..."
  ufw allow 62540/tcp
  ufw allow 62541/tcp
  echo "Allowing OPC/UA Data Access Server on ports 62546 and 62547..."
  ufw allow 62546/tcp
  ufw allow 62547/tcp
  echo "Allowing OPC/UA Generic Client on ports 61210 and 61211..."
  ufw allow 61210/tcp
  ufw allow 61211/tcp
  echo "Enabling UFW..."
  ufw enable
  echo "UFW firewall configuration completed. Current status:"
  ufw status verbose
  echo "Firewall setup complete."
}

# Install Cockpit
install_cockpit() {
    echo "Installing Cockpit..."
    apt-get install -y cockpit cockpit-bridge cockpit-networkmanager cockpit-packagekit cockpit-pcp cockpit-storaged cockpit-system cockpit-ws
    echo "Configure Cockpit to start on boot..."
    systemctl enable --now cockpit.socket
    echo "Starting Cockpit..."
    systemctl start cockpit

    echo "Opening Cockpit port in the firewall..."
    if command -v ufw &> /dev/null; then
        ufw allow 9090/tcp
    else
        echo "UFW is not installed."
    fi

    # Prompt user to choose network management tool
    echo -e "\nNetwork Manager Choice:"
    echo -e "1) Use NetworkManager (Recommended for dynamic and desktop environments)"
    echo -e "   - Pros: Easier management through GUI tools, better for mobile and changing environments."
    echo -e "   - Network-manager package, is a dependency of Cockpit's network management capabilities."
    echo -e "   - Cons: More complex, higher resource usage.\n"
    echo -e "2) Use ifupdown (Traditional method, recommended for static server environments)"
    echo -e "   - Pros: Simpler, lower resource usage."
    echo -e "   - Cons: Manual configuration, less flexible.\n"
    echo -n "Please enter your choice (1 or 2, Or 'x' to do nothing): "
    read choice

    case $choice in
        1)
            echo "You chose NetworkManager."
            # Backup /etc/network/interfaces
            if [ -f /etc/network/interfaces ]; then
                cp /etc/network/interfaces /etc/network/interfaces.bak
                echo "Backup of /etc/network/interfaces created as /etc/network/interfaces.bak."
            fi
            # Comment out interfaces in /etc/network/interfaces
            sed -i '/^auto/s/^/#/' /etc/network/interfaces
            sed -i '/^iface/s/^/#/' /etc/network/interfaces
            echo "Interfaces in /etc/network/interfaces have been commented out."
            systemctl restart NetworkManager
            echo "NetworkManager is now managing the network interfaces."
            ;;
        2)
            echo "You chose ifupdown."
            echo "No changes will be made to /etc/network/interfaces."
            ;;
        *)
            echo "Invalid choice. No changes will be made."
            ;;
    esac
  
  # Check for Cockpit service status
  if [ -f "$ISSUE_FILE_COCKPIT" ]; then
      echo "Cockpit is installed."
      COCKPIT_ACTIVE="active"
      # Read and display the URL from the issue file
      echo "Reading web console URL from $ISSUE_FILE_COCKPIT:"
      cat "$ISSUE_FILE_COCKPIT"
  else
    echo "Cockpit is not installed."
    COCKPIT_ACTIVE="not installed"
  fi
  echo -e "Cockpit Status: \033[1;32m$COCKPIT_ACTIVE\033[0m"
  [ "$COCKPIT_ACTIVE" = "active" ] && echo "Cockpit console: https://${HOSTNAME}:9090/"
  echo " "
}

# Install Docker and Docker Compose
install_docker() {
  echo "Installing Docker and Docker Compose..."
  apt-get remove -y docker docker-engine docker.io containerd runc
  apt-get update
  apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
  curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
  echo "Configure Docker to start on boot..."
  systemctl enable docker
  echo "Starting Docker..."
  systemctl start docker
}

# Install LazyDocker
install_lazydocker() {
    echo "Would you like to install LazyDocker using Docker or by downloading the binary?"
    echo "1) Install with Docker"
    echo "2) Download binary with curl"
    echo "x) quit install"
    echo -n "Please enter your choice (1 or 2 or x to quit install): "
    read choice

    case $choice in
        1)
            echo "You chose to install LazyDocker with Docker."
            echo "Installing LazyDocker..."
            docker run --rm -it -v /var/run/docker.sock:/var/run/docker.sock -v $HOME/.config/lazydocker:/.config/jesseduffield/lazydocker lazyteam/lazydocker
            echo "alias lzd='docker run --rm -it -v /var/run/docker.sock:/var/run/docker.sock -v $HOME/.config/lazydocker:/.config/jesseduffield/lazydocker lazyteam/lazydocker'" >> ~/.bashrc
            echo "alias lzd='docker run --rm -it -v /var/run/docker.sock:/var/run/docker.sock -v $HOME/.config/lazydocker:/.config/jesseduffield/lazydocker lazyteam/lazydocker'" >> ~/.zshrc
            source ~/.bashrc
            source ~/.zshrc
            echo "LazyDocker installed and alias 'lzd' added to your shell configuration."
            echo "To see keybinding go to: https://github.com/jesseduffield/lazydocker/tree/master/docs/keybindings"
            ;;
        2)
            echo "You chose to download the LazyDocker binary with curl."
            echo "Installing LazyDocker..."
            curl https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh | bash
            echo "alias lzd='$HOME/.local/bin/lazydocker'" >> ~/.bashrc
            echo "alias lzd='$HOME/.local/bin/lazydocker'" >> ~/.zshrc
            source ~/.bashrc
            source ~/.zshrc
            echo "LazyDocker installed and alias 'lzd' added to your shell configuration."
            echo "To see keybinding go to: https://github.com/jesseduffield/lazydocker/tree/master/docs/keybindings"
            ;;
        *)
            echo "No installation performed."
            ;;
    esac
}

# Install other necessary programs
install_other_programs() {
  echo "Installing other programs..."
  echo "sudo: Allows users to run programs with the security privileges of another user, typically the superuser (root)."
  echo "appstream: A software component that provides metadata for software applications and services in the Linux ecosystem. It is used to create a unified software center experience across different Linux distributions."
  echo "bmon: A bandwidth monitor and rate estimator for network interfaces. It provides a simple interface for monitoring and visualizing the bandwidth usage of network interfaces."
  echo "curl: A command-line tool and library for transferring data with URLs. It supports various protocols, including HTTP, HTTPS, FTP, and many others. It is commonly used for downloading files and interacting with REST APIs."
  echo "dnsutils: A collection of utilities for querying DNS (Domain Name System) servers. It includes tools like dig, nslookup, and host, which are useful for troubleshooting DNS issues."
  echo "exfat-fuse: A FUSE (Filesystem in Userspace) module to enable read and write support for the exFAT filesystem. exFAT is a file system optimized for flash drives and is used on many SD cards and USB drives."
  echo "exfat-utils: Utilities for managing exFAT filesystems, including tools to create, check, label, and repair exFAT filesystems."
  echo "gnupg: A complete and free implementation of the OpenPGP standard, allowing you to encrypt and sign your data and communications. It includes tools like gpg for encryption, signing, and key management."
  echo "gpg-agent: A daemon to manage private keys independently from any protocol. It is used by GnuPG and other applications that need to handle private keys."
  echo "gpgconf: A utility to configure and manage GnuPG options."
  echo "lm-sensors: A package that provides tools and drivers for monitoring the temperatures, voltage, and fans of your system. It is useful for keeping an eye on the hardware health of your machine."
  echo "mc (Midnight Commander): A text-mode file manager for Unix-like systems. It provides a user-friendly interface for managing files and directories, including support for copy, move, delete, and edit operations."
  echo "net-tools: A collection of programs for controlling the network subsystem of the Linux kernel. It includes tools like ifconfig, netstat, route, and others. Note that net-tools is considered deprecated in favor of iproute2."
  echo "nfs-common: Contains the support files and scripts needed to use NFS (Network File System) on client systems. NFS allows you to share directories over a network."
  echo "ntfs-3g: A FUSE driver that provides read and write access to NTFS (New Technology File System) partitions, commonly used on Windows systems."
  echo "rsync: A fast and versatile file copying tool used for local and remote file synchronization. It efficiently transfers and synchronizes files between computers and directories by only copying the differences between source and destination."
  echo "rsyslog: A rocket-fast system for log processing. It offers high-performance, great security features, and modularity. Rsyslog is commonly used for collecting and forwarding log messages in Unix and Unix-like systems."
  echo "vim: A highly configurable text editor built to enable efficient text editing. It is an improved version of the vi editor, with additional features like syntax highlighting, code folding, and extended plugins."
  echo "=================================================================================================================================================================================================================="
  echo "Install all this programs? Enter choice (1 install x quit)"
    case $choice in
        1)
            echo "Installing with"
            echo "apt-get install -y sudo appstream bmon curl dnsutils exfat-fuse exfat-utils gnupg gpg-agent gpgconf lm-sensors mc net-tools nfs-common ntfs-3g rsync rsyslog vim"
            apt-get install -y sudo appstream bmon curl dnsutils exfat-fuse exfat-utils gnupg gpg-agent gpgconf lm-sensors mc net-tools nfs-common ntfs-3g rsync rsyslog vim
            ;;
        *)
            echo "No installation performed."
            ;;
    esac

}

# Install WAGO login script
install_wago_login() {
  echo "Backup old WAGO_LOGIN"
  # Check if the file exists
  if [ -f /etc/WAGO_LOGIN ]; then
      # If the file exists, copy it to a new file with a .old extension
      cp /etc/WAGO_LOGIN /etc/WAGO_LOGIN.old
      echo "File /etc/WAGO_LOGIN found and copied to /etc/WAGO_LOGIN.old"
  else
      # If the file does not exist, print a message
      echo "File /etc/WAGO_LOGIN does not exist"
  fi
  echo "Downloading WAGO_LOGIN file from GitHub..."
  sudo curl -o /etc/WAGO_LOGIN https://raw.githubusercontent.com/espenbo/wagoEdgeStart/main/WagoLogin/WAGO_LOGIN

  echo "Changing owner and permissions of WAGO_LOGIN file..."
  sudo chown root:root /etc/WAGO_LOGIN
  sudo chmod 755 /etc/WAGO_LOGIN
  echo "Checking if WAGO_LOGIN is already added to /etc/profile..."
  if ! grep -q "/etc/WAGO_LOGIN" /etc/profile; then
    echo "Adding WAGO_LOGIN to /etc/profile..."
    sudo sed -i '/export PATH/a /etc/WAGO_LOGIN' /etc/profile
  else
    echo "WAGO_LOGIN is already added to /etc/profile."
  fi
}

# Install Samba and domain functionality
install_samba_domain() {
  echo "Installing necessary packages for domain connection..."
  apt-get install -y realmd sssd sssd-tools libnss-sss libpam-sss adcli samba-common-bin oddjob oddjob-mkhomedir packagekit
}

# Setup Samba and join domain
setup_samba_domain() {
  echo "Discovering and joining the domain..."
  realm discover yourdomain.com
  realm join yourdomain.com
  echo "Configuring Samba..."
  sed -i '/\[global\]/a workgroup = YOURDOMAIN\nsecurity = ads\nrealm = YOURDOMAIN.COM' /etc/samba/smb.conf
  echo "Starting Samba services..."
  systemctl restart smbd nmbd
  systemctl enable smbd nmbd
}

# Install OPC UA Commander
install_opcua_commander() {
    echo "Would you like to install OPC UA Commander using Snap, NPM, or Docker?"
    echo "1) Install with Snap"
    echo "   - Pros: Easy to install and manage, automatic updates, isolated from the rest of the system."
    echo "   - Cons: Performance overhead, limited customization, larger storage usage."
    echo "2) Install with NPM"
    echo "   - Pros: Flexible, integrates well with Node.js, portable."
    echo "   - Cons: More complex dependency management, manual updates, potential for conflicts with other NPM packages."
    echo "3) Install with Docker"
    echo "   - Pros: Strong isolation, portability, reproducibility."
    echo "   - Cons: Added complexity, higher resource usage, larger storage usage."
    echo -n "Please enter your choice (1, 2, or 3. x for exit): "
    read choice
    case $choice in
        1)
            echo "You chose to install OPC UA Commander with Snap."
            echo "Installing OPC UA Commander..."
            apt update
            apt install -y snapd
            snap install core
            snap install opcua-commander
            echo "OPC UA Commander installed using Snap."
            ;;
        2)
            echo "You chose to install OPC UA Commander with NPM."

            echo "Checking for Node.js..."
            if ! command -v nodejs &> /dev/null; then
                echo "Node.js is not installed. Installing Node.js..."
                install_nodejs
            fi
            echo "Installing OPC UA Commander..."
            npm install -g opcua-commander
            opcua-commander -e opc.tcp://localhost:26543 &
            echo "OPC UA Commander installed using NPM."
            echo "alias opcua-commander='opcua-commander -e opc.tcp://localhost:26543'" >> ~/.bashrc
            echo "alias opcua-commander='opcua-commander -e opc.tcp://localhost:26543'" >> ~/.zshrc
            source ~/.bashrc
            source ~/.zshrc
            echo "Alias 'opcua-commander' added to your shell configuration."
            ;;
        3)
            echo "You chose to install OPC UA Commander with Docker."
            echo "Checking for Docker..."
            if ! command -v docker &> /dev/null; then
                echo "Docker is not installed. Installing Docker..."
                install_docker
            fi
            echo "Building Docker image for OPC UA Commander..."
            docker build . -t commander
            echo "Running OPC UA Commander Docker container..."
            docker run -it commander -e opc.tcp://localhost:26543
            echo "alias opcua-commander='docker run -it commander -e opc.tcp://localhost:26543'" >> ~/.bashrc
            echo "alias opcua-commander='docker run -it commander -e opc.tcp://localhost:26543'" >> ~/.zshrc
            source ~/.bashrc
            source ~/.zshrc
            echo "OPC UA Commander Docker container is running and alias 'opcua-commander' added to your shell configuration."
            ;;
        *)
            echo "Invalid choice. No installation performed."
            ;;
    esac
}

# Install Node.js
install_nodejs() {
    echo "Checking for Docker..."
        if ! command -v nodejs &> /dev/null; then
                echo "Node.js is not installed. Installing Node.js..."
    
                echo "Choose a method to install Node.js:"
                echo "1) Install from Debian repository (Default APT)"
                echo "   - Pros: Simple, stable version from Debian repository."
                echo "   - Cons: Might not be the latest version."
                echo "2) Install from NodeSource"
                echo "   - Pros: Allows you to choose specific Node.js versions, often newer."
                echo "   - Cons: Slightly more complex setup."
                echo "3) Install using NVM (Node Version Manager)"
                echo "   - Pros: Manage multiple Node.js versions, easy switching between versions."
                echo "   - Cons: Requires additional setup."
                echo -n "Please enter your choice (1, 2, or 3): "
                read choice

                case $choice in
                    1)
                        echo "You chose to install Node.js from the Debian repository."
                        echo "Updating package list..."
                        apt update
                        echo "Installing Node.js..."
                        apt install -y nodejs
                        echo "Node.js installed."
                        nodejs -v
                        ;;
                    2)
                        echo "You chose to install Node.js from NodeSource."
                        echo "Installing required initial packages..."
                        apt install -y curl apt-transport-https ca-certificates
                        echo "Importing NodeSource GPG key..."
                        curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /usr/share/keyrings/nodesource.gpg
                        echo "Enter the Node.js version you want to install (e.g., 16, 18, 20): "
                        read NODE_MAJOR
                        echo "Adding NodeSource repository for Node.js $NODE_MAJOR..."
                        echo "deb [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list
                        echo "Updating package list..."
                        apt update
                        echo "Installing Node.js..."
                        apt install -y nodejs
                        echo "Node.js installed."
                        node -v
                        ;;
                    3)
                        echo "You chose to install Node.js using NVM."
                        echo "Installing NVM..."
                        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash
                        source ~/.bashrc
                        source ~/.zshrc
                        echo "NVM installed."
                        echo "Listing available Node.js versions..."
                        nvm ls-remote
                        echo "Enter the Node.js version you want to install (e.g., 18.16.0): "
                        read NODE_VERSION
                        echo "Installing Node.js version $NODE_VERSION..."
                        nvm install $NODE_VERSION
                        echo "Node.js $NODE_VERSION installed."
                        node -v
                        ;;
                    *)
                        echo "Invalid choice. No installation performed."
                        ;;
                esac
    else
        echo "Node.js is installed allready"
    fi
}

Install_nodered() {
    echo "https://github.com/node-red/linux-installers The command line for installing on a Debian based OS is:"
    echo "bash <(curl -sL https://raw.githubusercontent.com/node-red/linux-installers/master/deb/update-nodejs-and-nodered)"
    bash <(curl -sL https://raw.githubusercontent.com/node-red/linux-installers/master/deb/update-nodejs-and-nodered)
    echo "Ensure you have the build tools installed if you are going to install extra nodes."
    apt install -y build-essential
}

# Function to install unattended-upgrades
install_unattended_upgrades() {
    echo "Updating package lists..."
    apt update
    echo "Installing unattended-upgrades..."
    apt install -y unattended-upgrades

# Function to configure automatic updates
    config_file="/etc/apt/apt.conf.d/50unattended-upgrades"
    echo "Configuring automatic updates..."

    # Backup the original configuration file
    cp $config_file ${config_file}.bak
    echo "Backup of the original configuration file created at ${config_file}.bak."

    # Enable necessary updates
    sed -i 's#//\("\o.*-updates";\)#\1#' $config_file
    sed -i 's#//\("\o.*-proposed-updates";\)#\1#' $config_file
    sed -i 's#//\("\o.*label=Debian";\)#\1#' $config_file
    sed -i 's#//\("\o.*label=Debian-Security";\)#\1#' $config_file

# Function to configure email notifications    
    config_file="/etc/apt/apt.conf.d/50unattended-upgrades"
    echo -n "Would you like to enable email notifications for updates? (yes/no): "
    read enable_email

    if [ "$enable_email" == "yes" ]; then
        echo -n "Please enter your email address: "
        read email_address
        sed -i "s#//Unattended-Upgrade::Mail.*#Unattended-Upgrade::Mail \"$email_address\";#" $config_file
        echo "Email notifications configured for $email_address."
    else
        echo "Email notifications not enabled."
    fi

# Function to enable automatic removal of unused dependencies
    config_file="/etc/apt/apt.conf.d/50unattended-upgrades"
    echo "Enabling automatic removal of unused dependencies..."
    sed -i 's#//Unattended-Upgrade::Remove-Unused-Dependencies.*#Unattended-Upgrade::Remove-Unused-Dependencies "true";#' $config_file

# Function to enable automatic updates
    echo "Enabling automatic updates..."
    dpkg-reconfigure --priority=low unattended-upgrades

    echo "unattended-upgrades installation and configuration completed."
}



# Run all tasks sequentially
run_all_tasks() {
update_system
install_wago_login
install_other_programs
install_docker
install_tailscale
install_ufw
Install_nodered
install_cockpit
install_lazydocker
install_samba_domain
setup_samba_domain
install_opcua_commander
install_nodejs
install_unattended_upgrades
}

# Display menu and handle user choice
clear
show_menu
while [ "$opt" != '' ]
do
    if [ "$opt" = '' ]; then
        exit
    else
        case $opt in
            1) clear;
                option_picked "Option 1 Picked - Run 'apt update' and 'apt upgrade -y'";
                update_system;
                show_menu;
            ;;
            2) clear;
                option_picked "Option 2 Picked - Install WAGO login script";
                install_wago_login;
                show_menu;
            ;;
            3) clear;
                option_picked "Option 3 Picked - Install UFW firewall manager and open specific ports";
                install_ufw;
                show_menu;
            ;;
            4) clear;
                option_picked "Option 4 Picked - Install Tailscale";
                install_tailscale;
                show_menu;
            ;;
            5) clear;
                option_picked "Option 5 Picked - Install Cockpit web manager";
                install_cockpit;
                show_menu;
            ;;
            6) clear;
                option_picked "Option 6 Picked - Install Docker and Docker Compose";
                install_docker;
                show_menu;
            ;;
            7) clear;
                option_picked "Option 7 Picked - Install LazyDocker";
                install_lazydocker;
                show_menu;
            ;;
            8) clear;
                option_picked "Option 8 Picked - Install OPC UA Commander";
                install_opcua_commander;
                show_menu;
            ;;
            9) clear;
                option_picked "Option 9 Picked - Install Node-RED";
                Install_nodered;
                show_menu;
            ;;
            10) clear;
                option_picked "Option 10 Picked - Install Samba and domain functionality";
                install_samba_domain;
                show_menu;
            ;;
            11) clear;
                option_picked "Option 11 Picked - Install Node.js";
                install_nodejs;
                show_menu;
            ;;
            12) clear;
                option_picked "Option 12 Picked - Install other necessary programs";
                install_other_programs;
                show_menu;
            ;;
            13) clear;
                option_picked "Option 13 Picked - Setup Samba and join domain";
                setup_samba_domain;
                show_menu;
            ;;
            14) clear;
                option_picked "Option 14 Picked - Run all tasks sequentially";
                run_all_tasks;
                show_menu;
            ;;
            15) clear;
                install_unattended_upgrades
                show_menu;
            ;;
            16) clear;
                show_menu;
            ;;
            x) clear;
                printf "Exiting...\n";
                exit;
            ;;
            *)clear;
                option_picked "Pick an option from the menu";
                show_menu;
            ;;
        esac
    fi
done



