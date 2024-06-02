#!/bin/bash

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

# Function to display all reset tasks in a table format
show_reset_menu() {
    normal=$(echo "\033[m")
    menu=$(echo "\033[36m") #blue
    number=$(echo "\033[33m") #yellow
    fgred=$(echo "\033[31m")
    printf "\n${menu}********* System Reset Tool ***********${normal}\n"
    printf "${menu} ${number} 1)${menu} List updates ${normal}\n"
    printf "${menu} ${number} 2)${menu} Uninstall Tailscale ${normal}\n"
    printf "${menu} ${number} 3)${menu} Reset UFW firewall settings ${normal}\n"
    printf "${menu} ${number} 4)${menu} Uninstall Cockpit web manager ${normal}\n"
    printf "${menu} ${number} 5)${menu} Uninstall Docker and Docker Compose ${normal}\n"
    printf "${menu} ${number} 6)${menu} Uninstall Samba and domain functionality ${normal}\n"
    printf "${menu} ${number} 7)${menu} Uninstall other necessary programs ${normal}\n"
    printf "${menu} ${number} 8)${menu} Remove WAGO login script ${normal}\n"
    printf "${menu} ${number} 9)${menu} Leave and reset Samba domain ${normal}\n"
    printf "${menu} ${number} 10)${menu} Uninstall OPC UA Commander ${normal}\n"
    printf "${menu} ${number} 11)${menu} Uninstall Node.js ${normal}\n"
    printf "${menu} ${number} 12)${menu} Uninstall Node-RED ${normal}\n"
    printf "${menu} ${number} 13)${menu} Uninstall unattended-upgrades ${normal}\n"
    printf "${menu} ${number} 14)${menu} Run all reset tasks sequentially ${normal}\n"
    printf "${menu} ${number} x)${menu} Exit ${normal}\n"
    printf "Please enter a menu option and enter or ${fgred}x to exit. ${normal}"
    read -r opt
}

option_picked() {
    msgcolor=$(echo "\033[01;31m") # bold red
    normal=$(echo "\033[00;00m") # normal white
    message=${1:-"${normal}Error: No message passed"}
    printf "${msgcolor}${message}${normal}\n"
}

# List system updates
list_system_updates() {
    echo "Checking installed updates."
    apt list --upgradable
}

# Uninstall Tailscale
uninstall_tailscale() {
    echo "Uninstalling Tailscale..."
    apt-get remove --purge -y tailscale
    apt-get autoremove -y
    rm -rf /var/lib/tailscale
}

# Reset UFW firewall settings
reset_ufw() {
    echo "Resetting UFW settings..."
    ufw disable
    ufw reset
    apt-get remove --purge -y ufw
    apt-get autoremove -y
}

# Uninstall Cockpit
uninstall_cockpit() {
    echo "Uninstalling Cockpit..."
    apt-get remove --purge -y cockpit cockpit-bridge cockpit-networkmanager cockpit-packagekit cockpit-pcp cockpit-storaged cockpit-system cockpit-ws
    systemctl stop cockpit
    systemctl disable cockpit.socket
    apt-get autoremove -y
}

# Uninstall Docker and Docker Compose
uninstall_docker() {
    echo "Uninstalling Docker and Docker Compose..."
    apt-get remove --purge -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    apt-get autoremove -y
    rm -rf /var/lib/docker
    rm -rf /etc/docker
    rm -rf /var/run/docker.sock
}

# Uninstall other necessary programs
uninstall_other_programs() {
    echo "Uninstalling other programs..."
    apt-get remove --purge -y sudo appstream bmon curl dnsutils exfat-fuse exfat-utils gnupg gpg-agent gpgconf lm-sensors mc net-tools nfs-common ntfs-3g rsync rsyslog vim
    apt-get autoremove -y
}

# Remove WAGO login script
remove_wago_login() {
    echo "Removing WAGO_LOGIN file..."
    rm -f /etc/WAGO_LOGIN
    sed -i '/\/etc\/WAGO_LOGIN/d' /etc/profile
}

# Uninstall Samba and domain functionality
uninstall_samba_domain() {
    echo "Uninstalling Samba and domain functionality..."
    apt-get remove --purge -y realmd sssd sssd-tools libnss-sss libpam-sss adcli samba-common-bin oddjob oddjob-mkhomedir packagekit
    apt-get autoremove -y
}

# Leave and reset Samba domain
reset_samba_domain() {
    echo "Leaving Samba domain..."
    realm leave yourdomain.com
    echo "Resetting Samba configuration..."
    sed -i '/workgroup = YOURDOMAIN/d' /etc/samba/smb.conf
    sed -i '/security = ads/d' /etc/samba/smb.conf
    sed -i '/realm = YOURDOMAIN.COM/d' /etc/samba/smb.conf
    systemctl stop smbd nmbd
    systemctl disable smbd nmbd
    apt-get remove --purge -y samba
    apt-get autoremove -y
}

# Uninstall OPC UA Commander
uninstall_opcua_commander() {
    echo "Uninstalling OPC UA Commander..."
    snap remove opcua-commander || npm uninstall -g opcua-commander || docker rmi commander
}

# Uninstall Node.js
uninstall_nodejs() {
    echo "Uninstalling Node.js..."
    apt-get remove --purge -y nodejs
    apt-get autoremove -y
    rm -rf /usr/local/nvm
    rm -rf ~/.nvm
    sed -i '/NVM_DIR/d' ~/.bashrc ~/.zshrc
}

# Uninstall Node-RED
uninstall_nodered() {
    echo "Uninstalling Node-RED..."
    npm uninstall -g --unsafe-perm node-red
    rm -rf /usr/lib/node_modules/node-red
}

# Uninstall unattended-upgrades
uninstall_unattended_upgrades() {
    echo "Uninstalling unattended-upgrades..."
    apt-get remove --purge -y unattended-upgrades
    apt-get autoremove -y
}

# Run all reset tasks sequentially
run_all_reset_tasks() {
    list_system_updates
    uninstall_tailscale
    reset_ufw
    uninstall_cockpit
    uninstall_docker
    uninstall_samba_domain
    uninstall_other_programs
    remove_wago_login
    reset_samba_domain
    uninstall_opcua_commander
    uninstall_nodejs
    uninstall_nodered
    uninstall_unattended_upgrades
}

# Display menu and handle user choice
clear
show_reset_menu
while [ "$opt" != '' ]
do
    if [ "$opt" = '' ]; then
        exit
    else
        case $opt in
            1) clear;
                option_picked "Option 1 Picked - List updates";
                list_system_updates;
                show_reset_menu;
            ;;
            2) clear;
                option_picked "Option 2 Picked - Uninstall Tailscale";
                uninstall_tailscale;
                show_reset_menu;
            ;;
            3) clear;
                option_picked "Option 3 Picked - Reset UFW firewall settings";
                reset_ufw;
                show_reset_menu;
            ;;
            4) clear;
                option_picked "Option 4 Picked - Uninstall Cockpit web manager";
                uninstall_cockpit;
                show_reset_menu;
            ;;
            5) clear;
                option_picked "Option 5 Picked - Uninstall Docker and Docker Compose";
                uninstall_docker;
                show_reset_menu;
            ;;
            6) clear;
                option_picked "Option 6 Picked - Uninstall Samba and domain functionality";
                uninstall_samba_domain;
                show_reset_menu;
            ;;
            7) clear;
                option_picked "Option 7 Picked - Uninstall other necessary programs";
                uninstall_other_programs;
                show_reset_menu;
            ;;
            8) clear;
                option_picked "Option 8 Picked - Remove WAGO login script";
                remove_wago_login;
                show_reset_menu;
            ;;
            9) clear;
                option_picked "Option 9 Picked - Leave and reset Samba domain";
                reset_samba_domain;
                show_reset_menu;
            ;;
            10) clear;
                option_picked "Option 10 Picked - Uninstall OPC UA Commander";
                uninstall_opcua_commander;
                show_reset_menu;
            ;;
            11) clear;
                option_picked "Option 11 Picked - Uninstall Node.js";
                uninstall_nodejs;
                show_reset_menu;
            ;;
            12) clear;
                option_picked "Option 12 Picked - Uninstall Node-RED";
                uninstall_nodered;
                show_reset_menu;
            ;;
            13) clear;
                option_picked "Option 13 Picked - Uninstall unattended-upgrades";
                uninstall_unattended_upgrades;
                show_reset_menu;
            ;;
            14) clear;
                option_picked "Option 14 Picked - Run all reset tasks sequentially";
                run_all_reset_tasks;
                show_reset_menu;
            ;;
            x) clear;
                printf "Exiting...\n";
                exit;
            ;;
            *) clear;
                option_picked "Pick an option from the menu";
                show_reset_menu;
            ;;
        esac
    fi
done
