#!/bin/bash

# Initialize service status variables
COCKPIT_ACTIVE="inactive"
PORTAINER_ACTIVE="inactive"
ISSUE_FILE_COCKPIT="/etc/issue.d/cockpit.issue"  # Ensure this path is correct

# Constants
BLUE="\033[36m"
YELLOW="\033[33m"
RED="\033[31m"
NORMAL="\033[m"
BOLD_RED="\033[01;31m"

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root or with sudo"
    exit 1
fi

# Trap for cleanup on exit
trap cleanup EXIT

# Helper Functions

log() {
    local message="$1"
    local color="$2"
    echo -e "${color}${message}${NORMAL}"
}

error_exit() {
    log "$1" "$BOLD_RED"
    exit 1
}

validate_command() {
    command -v "$1" &> /dev/null || error_exit "$1 is required but not installed. Aborting."
}

run_command() {
    local description="$1"
    local command="$2"
    log "$description" "$BLUE"
    eval "$command"
    [ $? -ne 0 ] && error_exit "Failed to: $description"
}

backup_file() {
    local file_path="$1"
    if [ -f "$file_path" ]; then
        cp "$file_path" "${file_path}.bak"
        log "Backup of $file_path created at ${file_path}.bak" "$YELLOW"
    fi
}

# Functions for system setup tasks

update_system() {
    run_command "Updating the system..." "apt update && apt upgrade -y"
}

install_package() {
    local package="$1"
    run_command "Installing $package..." "apt-get install -y $package"
}

install_tailscale() {
    run_command "Installing Tailscale..." "curl -fsSL https://tailscale.com/install.sh | sh && tailscale up"
}

install_ufw() {
    run_command "Installing and configuring UFW..." "
        apt-get install -y ufw &&
        ufw reset &&
        ufw default deny incoming &&
        ufw default allow outgoing &&
        ufw allow 22/tcp &&
        ufw allow 80/tcp &&
        ufw allow 443/tcp &&
        ufw allow 502/tcp &&
        ufw allow 4840/tcp &&
        ufw allow 4843/tcp &&
        ufw allow 62540/tcp &&
        ufw allow 62541/tcp &&
        ufw allow 62546/tcp &&
        ufw allow 62547/tcp &&
        ufw allow 61210/tcp &&
        ufw allow 61211/tcp &&
        ufw enable &&
        ufw status verbose"
}

install_cockpit() {
    run_command "Installing Cockpit..." "
        apt-get install -y cockpit &&
        systemctl enable --now cockpit.socket &&
        systemctl start cockpit &&
        ufw allow 9090/tcp"
    if [ -f "$ISSUE_FILE_COCKPIT" ]; then
        COCKPIT_ACTIVE="active"
        log "Cockpit web console URL:" "$YELLOW"
        cat "$ISSUE_FILE_COCKPIT"
    else
        COCKPIT_ACTIVE="not installed"
    fi
    log "Cockpit Status: $COCKPIT_ACTIVE" "$YELLOW"
    [ "$COCKPIT_ACTIVE" = "active" ] && log "Cockpit console: https://${HOSTNAME}:9090/" "$YELLOW"
}

install_docker() {
    run_command "Installing Docker and Docker Compose..." "
        apt-get remove -y docker docker-engine docker.io containerd runc &&
        apt-get update &&
        apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release &&
        curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg &&
        echo 'deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable' | tee /etc/apt/sources.list.d/docker.list > /dev/null &&
        apt-get update &&
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin &&
        systemctl enable docker &&
        systemctl start docker"
}

install_lazydocker() {
    local choice
    log "Would you like to install LazyDocker using Docker or by downloading the binary?" "$YELLOW"
    log "1) Install with Docker" "$YELLOW"
    log "2) Download binary with curl" "$YELLOW"
    log "x) Quit install" "$YELLOW"
    read -rp "Please enter your choice (1, 2, or x): " choice

    case $choice in
        1)
            run_command "Installing LazyDocker with Docker..." "
                docker run --rm -it -v /var/run/docker.sock:/var/run/docker.sock -v \$HOME/.config/lazydocker:/.config/jesseduffield/lazydocker lazyteam/lazydocker &&
                echo 'alias lzd=\"docker run --rm -it -v /var/run/docker.sock:/var/run/docker.sock -v \$HOME/.config/lazydocker:/.config/jesseduffield/lazydocker lazyteam/lazydocker\"' >> ~/.bashrc &&
                source ~/.bashrc"
            ;;
        2)
            run_command "Downloading LazyDocker binary with curl..." "
                curl https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh | bash &&
                echo 'alias lzd=\"\$HOME/.local/bin/lazydocker\"' >> ~/.bashrc &&
                source ~/.bashrc"
            ;;
        *)
            log "No installation performed." "$RED"
            ;;
    esac
}

install_other_programs() {
    run_command "Installing other programs..." "
        apt-get install -y sudo appstream bmon curl dnsutils exfat-fuse exfat-utils gnupg gpg-agent gpgconf lm-sensors mc net-tools nfs-common ntfs-3g rsync rsyslog vim"
}

install_wago_login() {
    run_command "Installing WAGO login script..." "
        [ -f /etc/WAGO_LOGIN ] && cp /etc/WAGO_LOGIN /etc/WAGO_LOGIN.old
        curl -o /etc/WAGO_LOGIN https://raw.githubusercontent.com/espenbo/wagoEdgeStart/main/WAGO_LOGIN &&
        chown root:root /etc/WAGO_LOGIN &&
        chmod 755 /etc/WAGO_LOGIN &&
        grep -q '/etc/WAGO_LOGIN' /etc/profile || sed -i '/export TMOUT/a /etc/WAGO_LOGIN' /etc/profile"
}

install_samba_domain() {
    run_command "Installing necessary packages for domain connection..." "
        apt-get install -y realmd sssd sssd-tools libnss-sss libpam-sss adcli samba-common-bin oddjob oddjob-mkhomedir packagekit"
}

setup_samba_domain() {
    run_command "Discovering and joining the domain..." "
        realm discover yourdomain.com &&
        realm join yourdomain.com"
    run_command "Configuring Samba..." "
        sed -i '/\[global\]/a workgroup = YOURDOMAIN\nsecurity = ads\nrealm = YOURDOMAIN.COM' /etc/samba/smb.conf &&
        systemctl restart smbd nmbd &&
        systemctl enable smbd nmbd"
}

install_opcua_commander() {
    local choice
    log "Would you like to install OPC UA Commander using Snap, NPM, or Docker?" "$YELLOW"
    log "1) Install with Snap" "$YELLOW"
    log "2) Install with NPM" "$YELLOW"
    log "3) Install with Docker" "$YELLOW"
    read -rp "Please enter your choice (1, 2, or 3): " choice

    case $choice in
        1)
            run_command "Installing OPC UA Commander with Snap..." "
                apt update &&
                apt install -y snapd &&
                snap install core &&
                snap install opcua-commander"
            ;;
        2)
            if ! command -v nodejs &> /dev/null; then
                install_nodejs
            fi
            run_command "Installing OPC UA Commander with NPM..." "
                npm install -g opcua-commander &&
                opcua-commander -e opc.tcp://localhost:26543 &"
            ;;
        3)
            if ! command -v docker &> /dev/null; then
                install_docker
            fi
            run_command "Building and running OPC UA Commander Docker container..." "
                docker build . -t commander &&
                docker run -it commander -e opc.tcp://localhost:26543"
            ;;
        *)
            log "Invalid choice. No installation performed." "$RED"
            ;;
    esac
}

install_nodejs() {
    if ! command -v nodejs &> /dev/null; then
        log "Node.js is not installed. Installing Node.js..." "$YELLOW"
        local choice
        log "1) Install from Debian repository" "$YELLOW"
        log "2) Install from NodeSource" "$YELLOW"
        log "3) Install using NVM" "$YELLOW"
        read -rp "Please enter your choice (1, 2, or 3): " choice

        case $choice in
            1)
                run_command "Installing Node.js from Debian repository..." "
                    apt update &&
                    apt install -y nodejs"
                ;;
            2)
                run_command "Installing Node.js from NodeSource..." "
                    apt install -y curl apt-transport-https ca-certificates &&
                    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /usr/share/keyrings/nodesource.gpg &&
                    read -rp 'Enter the Node.js version you want to install (e.g., 16, 18, 20): ' NODE_MAJOR &&
                    echo 'deb [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_\$NODE_MAJOR.x nodistro main' | tee /etc/apt/sources.list.d/nodesource.list &&
                    apt update &&
                    apt install -y nodejs"
                ;;
            3)
                run_command "Installing Node.js using NVM..." "
                    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash &&
                    source ~/.bashrc &&
                    nvm ls-remote &&
                    read -rp 'Enter the Node.js version you want to install (e.g., 18.16.0): ' NODE_VERSION &&
                    nvm install \$NODE_VERSION"
                ;;
            *)
                log "Invalid choice. No installation performed." "$RED"
                ;;
        esac
    fi
}

install_nodered() {
    run_command "Installing Node-RED..." "
        bash <(curl -sL https://raw.githubusercontent.com/node-red/linux-installers/master/deb/update-nodejs-and-nodered) &&
        apt install -y build-essential"
}

install_unattended_upgrades() {
    run_command "Installing unattended-upgrades..." "
        apt update &&
        apt install -y unattended-upgrades"
    local config_file="/etc/apt/apt.conf.d/50unattended-upgrades"
    backup_file "$config_file"
    sed -i 's#//\("\o.*-updates";\)#\1#' "$config_file"
    sed -i 's#//\("\o.*-proposed-updates";\)#\1#' "$config_file"
    sed -i 's#//\("\o.*label=Debian";\)#\1#' "$config_file"
    sed -i 's#//\("\o.*label=Debian-Security";\)#\1#' "$config_file"
    read -rp "Enable email notifications for updates? (yes/no): " enable_email
    if [ "$enable_email" == "yes" ]; then
        read -rp "Enter your email address: " email_address
        sed -i "s#//Unattended-Upgrade::Mail.*#Unattended-Upgrade::Mail \"$email_address\";#" "$config_file"
    fi
    sed -i 's#//Unattended-Upgrade::Remove-Unused-Dependencies.*#Unattended-Upgrade::Remove-Unused-Dependencies "true";#' "$config_file"
    dpkg-reconfigure --priority=low unattended-upgrades
}

run_all_tasks() {
    update_system
    install_wago_login
    install_other_programs
    install_docker
    install_tailscale
    install_ufw
    install_nodered
    install_cockpit
    install_lazydocker
    install_samba_domain
    setup_samba_domain
    install_opcua_commander
    install_nodejs
    install_unattended_upgrades
}

# Display menu and handle user choice
show_menu() {
    printf "\n${BLUE}********* System Provisioning Tool ***********${NORMAL}\n"
    printf "${BLUE} ${YELLOW} 1)${BLUE} Run 'apt update' and 'apt upgrade -y' ${NORMAL}\n"
    printf "${BLUE} ${YELLOW} 2)${BLUE} Install WAGO login script ${NORMAL}\n"
    printf "${BLUE} ${YELLOW} 3)${BLUE} Install UFW firewall manager and open specific ports ${NORMAL}\n"
    printf "${BLUE} ${YELLOW} 4)${BLUE} Install Tailscale ${NORMAL}\n"
    printf "${BLUE} ${YELLOW} 5)${BLUE} Install Cockpit web manager ${NORMAL}\n"
    printf "${BLUE} ${YELLOW} 6)${BLUE} Install Docker and Docker Compose ${NORMAL}\n"
    printf "${BLUE} ${YELLOW} 7)${BLUE} Install LazyDocker. CLI docker manager. ${NORMAL}\n"
    printf "${BLUE} ${YELLOW} 8)${BLUE} Install OPC UA Commander ${NORMAL}\n"
    printf "${BLUE} ${YELLOW} 9)${BLUE} Install Node-RED ${NORMAL}\n"
    printf "${BLUE} ${YELLOW} 10)${BLUE} Install Samba and domain functionality ${NORMAL}\n"
    printf "${BLUE} ${YELLOW} 11)${BLUE} Install Node.js ${NORMAL}\n"
    printf "${BLUE} ${YELLOW} 12)${BLUE} Install other necessary programs ${NORMAL}\n"
    printf "${BLUE} ${YELLOW} 13)${BLUE} Setup Samba and join domain ${NORMAL}\n"
    printf "${BLUE} ${YELLOW} 14)${BLUE} Run all tasks sequentially ${NORMAL}\n"
    printf "${BLUE} ${YELLOW} 15)${BLUE} Install unattended-upgrades ${NORMAL}\n"
    printf "${BLUE} ${YELLOW} 16)${BLUE} Show menu ${NORMAL}\n"
    printf "${BLUE} ${YELLOW} x)${BLUE} Exit ${NORMAL}\n"
    printf "Please enter a menu option and enter or ${RED}x to exit. ${NORMAL}"
    read -r opt
}

cleanup() {
    log "Cleaning up..." "$YELLOW"
    # Add any cleanup tasks here
}

# Main loop
clear
show_menu
while [ "$opt" != '' ]
do
    case $opt in
        1) clear; option_picked "Option 1 Picked - Run 'apt update' and 'apt upgrade -y'"; update_system; show_menu ;;
        2) clear; option_picked "Option 2 Picked - Install WAGO login script"; install_wago_login; show_menu ;;
        3) clear; option_picked "Option 3 Picked - Install UFW firewall manager and open specific ports"; install_ufw; show_menu ;;
        4) clear; option_picked "Option 4 Picked - Install Tailscale"; install_tailscale; show_menu ;;
        5) clear; option_picked "Option 5 Picked - Install Cockpit web manager"; install_cockpit; show_menu ;;
        6) clear; option_picked "Option 6 Picked - Install Docker and Docker Compose"; install_docker; show_menu ;;
        7) clear; option_picked "Option 7 Picked - Install LazyDocker"; install_lazydocker; show_menu ;;
        8) clear; option_picked "Option 8 Picked - Install OPC UA Commander"; install_opcua_commander; show_menu ;;
        9) clear; option_picked "Option 9 Picked - Install Node-RED"; install_nodered; show_menu ;;
        10) clear; option_picked "Option 10 Picked - Install Samba and domain functionality"; install_samba_domain; show_menu ;;
        11) clear; option_picked "Option 11 Picked - Install Node.js"; install_nodejs; show_menu ;;
        12) clear; option_picked "Option 12 Picked - Install other necessary programs"; install_other_programs; show_menu ;;
        13) clear; option_picked "Option 13 Picked - Setup Samba and join domain"; setup_samba_domain; show_menu ;;
        14) clear; option_picked "Option 14 Picked - Run all tasks sequentially"; run_all_tasks; show_menu ;;
        15) clear; install_unattended_upgrades; show_menu ;;
        16) clear; show_menu ;;
        x) clear; log "Exiting..." "$YELLOW"; exit ;;
        *) clear; log "Pick an option from the menu" "$RED"; show_menu ;;
    esac
done
