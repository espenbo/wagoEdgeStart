#!/bin/bash

# Remove what setup_edge_computer.sh installed. Run it as a normal user, it uses sudo where it is needed.
# sudo, curl, gnupg and rsyslog are never removed: without sudo a normal user cannot manage the machine.

normal=`echo "\033[m"`
menu=`echo "\033[36m"` #blue
number=`echo "\033[33m"` #yellow
fgred=`echo "\033[31m"`

# Run as a normal user with sudo rights
check_user() {
    if [ "$EUID" -eq 0 ]; then
        printf "${fgred}Please run this as a normal user, without sudo. It asks for sudo when it is needed.${normal}\n"
        exit 1
    fi
    if ! command -v sudo &>/dev/null || ! sudo -v; then
        printf "${fgred}Your user needs sudo rights.${normal}\n"
        exit 1
    fi
}

menu_line() {
    printf "${menu} ${number}%3s)${menu} %s ${normal}\n" "$1" "$2"
}

# Display all reset tasks
show_reset_menu() {
    printf "\n${menu}********* WAGO Edge Reset ***********${normal}\n"
    printf "${fgred}Everything here removes programs. You are asked to confirm first.${normal}\n\n"
    menu_line 1 "Remove common tools"
    menu_line 2 "Remove WAGO login script"
    menu_line 3 "Remove automatic security updates"
    menu_line 4 "Remove firewall (UFW)"
    menu_line 5 "Remove Cockpit"
    menu_line 6 "Remove Tailscale"
    menu_line 7 "Remove Fail2ban"
    menu_line 8 "Remove file server (Samba). Shared files are kept"
    menu_line 9 "Leave the Windows domain"
    menu_line 10 "Remove Docker and Docker Compose"
    menu_line 11 "Remove LazyDocker"
    menu_line 12 "Remove Portainer"
    menu_line 13 "Remove Node-RED"
    menu_line 14 "Remove Node.js"
    menu_line 15 "Remove Java"
    menu_line 16 "Remove OPC UA Commander"
    menu_line 17 "Remove opcilloscope"
    menu_line 18 "Remove Mosquitto"
    menu_line 19 "Remove EKBPRO KNX Terminal"
    menu_line 20 "Remove InfluxDB"
    menu_line 21 "Remove Grafana"
    menu_line 22 "Remove Ignition"
    menu_line 23 "Remove Bitwarden CLI"
    menu_line 24 "Remove everything above"
    echo
    menu_line x "Exit"
    printf "Please enter a menu option: "
    read -r opt || exit 0
}

# Ask before removing something, only a typed yes continues
confirm() {
    printf "${fgred}%s${normal} Type yes to continue: " "$1"
    read -r answer
    [ "$answer" = "yes" ]
}

# Remove a container and its volumes if they exist: remove_container name volume...
remove_container() {
    local name="$1" volume
    shift
    command -v docker &>/dev/null || return 0
    if sudo docker ps -a --format '{{.Names}}' | grep -qx "$name"; then
        sudo docker rm -f "$name"
        for volume in "$@"; do
            sudo docker volume rm "$volume"
        done
    fi
}

# Programs installed with nvm are only found after this
load_nvm() {
    if [ -s "$HOME/.nvm/nvm.sh" ]; then
        . "$HOME/.nvm/nvm.sh"
    fi
}

purge() {
    sudo apt-get remove --purge -y "$@"
    sudo apt-get autoremove -y
}

# Remove common tools. sudo, curl, gnupg and rsyslog stay.
uninstall_other_programs() {
    confirm "This removes htop, tmux, vim, mc and the other common tools." || return 0
    purge appstream bmon dnsutils exfat-fuse htop iperf3 lm-sensors mbpoll mc ncdu net-tools nfs-common ntfs-3g tmux vim
}

remove_wago_login() {
    confirm "This removes the WAGO login script." || return 0
    sudo rm -f /etc/WAGO_LOGIN
    sudo sed -i '/\/etc\/WAGO_LOGIN/d' /etc/profile
}

uninstall_unattended_upgrades() {
    confirm "The machine no longer installs security updates by itself." || return 0
    purge unattended-upgrades
}

reset_ufw() {
    confirm "This removes the firewall, and all ports are open afterwards." || return 0
    sudo ufw --force disable
    sudo ufw --force reset
    purge ufw
}

uninstall_cockpit() {
    confirm "This removes Cockpit." || return 0
    sudo systemctl disable --now cockpit.socket
    purge cockpit cockpit-bridge cockpit-networkmanager cockpit-packagekit cockpit-pcp cockpit-storaged cockpit-system cockpit-ws
    if [ -f /etc/network/interfaces.bak ]; then
        echo "If NetworkManager took over the network, your old settings are in /etc/network/interfaces.bak"
    fi
}

uninstall_tailscale() {
    confirm "If you are connected through Tailscale, you lose the connection." || return 0
    purge tailscale
    sudo rm -rf /var/lib/tailscale
}

uninstall_fail2ban() {
    confirm "This removes Fail2ban." || return 0
    sudo systemctl disable --now fail2ban
    purge fail2ban
    sudo rm -f /etc/fail2ban/jail.d/sshd-systemd.conf
}

# The shared folders are not deleted, they can hold the only copy of the files
uninstall_file_server() {
    confirm "Other machines can no longer reach the shared folders. The files stay on this machine." || return 0
    sudo systemctl disable --now smbd nmbd
    purge samba
}

# Leave the Windows domain the machine is joined to
leave_domain() {
    local domain
    domain="$(realm list --name-only 2>/dev/null | head -n 1)"
    if [ -n "$domain" ]; then
        confirm "Domain users can no longer log in to this machine after leaving $domain." || return 0
        sudo realm leave "$domain"
    else
        echo "The machine is not in a domain."
        confirm "This removes the domain packages." || return 0
    fi
    purge realmd sssd sssd-tools libnss-sss libpam-sss adcli samba-common-bin oddjob oddjob-mkhomedir packagekit
}

uninstall_docker() {
    confirm "This removes Docker." || return 0
    purge docker-ce docker-ce-cli containerd.io docker-compose-plugin
    sudo rm -f /etc/apt/sources.list.d/docker.list /usr/share/keyrings/docker-archive-keyring.gpg
    if confirm "Also delete ALL containers, images and data in /var/lib/docker? This cannot be undone."; then
        sudo rm -rf /var/lib/docker /etc/docker
    fi
}

uninstall_lazydocker() {
    confirm "This removes LazyDocker." || return 0
    rm -f "$HOME/.local/bin/lazydocker"
    if command -v docker &>/dev/null; then
        sudo docker rmi lazyteam/lazydocker
    fi
    sed -i '/^alias lzd=/d' ~/.bashrc
}

uninstall_portainer() {
    confirm "This removes Portainer and its settings. Your other containers keep running." || return 0
    remove_container portainer portainer_data
}

uninstall_nodered() {
    confirm "This removes Node-RED. Your flows stay in ~/.node-red." || return 0
    sudo systemctl disable --now nodered.service
    sudo npm uninstall -g --unsafe-perm node-red
    sudo rm -f /lib/systemd/system/nodered.service
    sudo systemctl daemon-reload
}

uninstall_nodejs() {
    confirm "This removes Node.js. Node-RED, OPC UA Commander and the Bitwarden CLI from NPM stop working." || return 0
    purge nodejs npm
    sudo rm -f /etc/apt/sources.list.d/nodesource.list /usr/share/keyrings/nodesource.gpg
    rm -rf "$HOME/.nvm"
    sed -i '/NVM_DIR/d' ~/.bashrc
}

uninstall_java() {
    confirm "This removes Java." || return 0
    purge default-jre default-jdk
}

uninstall_opcua_commander() {
    confirm "This removes OPC UA Commander." || return 0
    if command -v snap &>/dev/null; then
        sudo snap remove opcua-commander
    fi
    if command -v docker &>/dev/null; then
        sudo docker rmi commander
    fi
    if command -v npm &>/dev/null; then
        if [[ "$(command -v npm)" == "$HOME"/* ]]; then
            npm uninstall -g opcua-commander
        else
            sudo npm uninstall -g opcua-commander
        fi
    fi
    sed -i '/^alias opcua-commander=/d' ~/.bashrc
}

uninstall_opcilloscope() {
    confirm "This removes opcilloscope." || return 0
    rm -f "$HOME/.local/bin/opcilloscope"
}

uninstall_mosquitto() {
    confirm "This removes the MQTT broker." || return 0
    purge mosquitto mosquitto-clients
}

# Remove the KNX server and program. The folder can hold customer files, so it is shown first.
uninstall_knx_terminal() {
    local folder="$HOME/ekbpro-knx-terminal-python"
    printf "${menu}Install directory ${number}[%s]${menu}: ${normal}" "$folder"
    read -r answer
    folder="${answer:-$folder}"
    confirm "This stops the KNX server and deletes $folder with the KNX project, plan.yaml and all logged data." || return 0
    sudo systemctl disable --now knxscada
    sudo rm -f /etc/systemd/system/knxscada.service
    sudo systemctl daemon-reload
    if [ -f "$folder/scada" ]; then
        rm -rf "$folder"
    else
        echo "$folder does not look like the KNX Terminal folder, it was not deleted."
    fi
}

uninstall_influxdb() {
    confirm "This removes InfluxDB and ALL stored measurements." || return 0
    remove_container influxdb influxdb2_data influxdb2_config influxdb3_data
    sudo systemctl disable --now influxdb
    purge influxdb2
    sudo rm -rf /var/lib/influxdb /etc/influxdb
    sudo rm -f /etc/apt/sources.list.d/influxdata.list /usr/share/keyrings/influxdata-archive.gpg
}

uninstall_grafana() {
    confirm "This removes Grafana and ALL dashboards." || return 0
    remove_container grafana grafana_data
    sudo systemctl disable --now grafana-server
    purge grafana
    sudo rm -f /etc/apt/sources.list.d/grafana.list /usr/share/keyrings/grafana.gpg
}

# The installer version is removed with its own uninstaller
uninstall_ignition() {
    confirm "This removes Ignition in Docker with ALL projects and settings." || return 0
    remove_container ignition ignition_data
    if [ -d /usr/local/bin/ignition ]; then
        echo "Ignition is also installed with the installer. Remove it with the uninstaller in /usr/local/bin/ignition"
    fi
}

# The login and the local copy of the vault go too. The account itself is not touched.
uninstall_bitwarden_cli() {
    confirm "This removes the Bitwarden CLI and its login on this machine. Your Bitwarden account is not touched." || return 0
    sudo rm -f /usr/local/bin/bw
    if command -v snap &>/dev/null; then
        sudo snap remove bw
    fi
    if command -v npm &>/dev/null; then
        if [[ "$(command -v npm)" == "$HOME"/* ]]; then
            npm uninstall -g @bitwarden/cli
        else
            sudo npm uninstall -g @bitwarden/cli
        fi
    fi
    rm -rf "$HOME/.config/Bitwarden CLI" "$HOME/snap/bw"
}

# Run all reset tasks. Each task still asks for confirmation.
run_all_reset_tasks() {
    confirm "You are asked about each program in turn." || return 0
    uninstall_bitwarden_cli
    uninstall_ignition
    uninstall_grafana
    uninstall_influxdb
    uninstall_knx_terminal
    uninstall_mosquitto
    uninstall_opcilloscope
    uninstall_opcua_commander
    uninstall_nodered
    uninstall_nodejs
    uninstall_java
    uninstall_portainer
    uninstall_lazydocker
    uninstall_docker
    uninstall_cockpit
    uninstall_fail2ban
    uninstall_file_server
    leave_domain
    remove_wago_login
    uninstall_other_programs
    uninstall_unattended_upgrades
    uninstall_tailscale
    reset_ufw
}

# Display menu and handle user choice
check_user
load_nvm
clear
while true; do
    show_reset_menu
    case $opt in
        1) uninstall_other_programs ;;
        2) remove_wago_login ;;
        3) uninstall_unattended_upgrades ;;
        4) reset_ufw ;;
        5) uninstall_cockpit ;;
        6) uninstall_tailscale ;;
        7) uninstall_fail2ban ;;
        8) uninstall_file_server ;;
        9) leave_domain ;;
        10) uninstall_docker ;;
        11) uninstall_lazydocker ;;
        12) uninstall_portainer ;;
        13) uninstall_nodered ;;
        14) uninstall_nodejs ;;
        15) uninstall_java ;;
        16) uninstall_opcua_commander ;;
        17) uninstall_opcilloscope ;;
        18) uninstall_mosquitto ;;
        19) uninstall_knx_terminal ;;
        20) uninstall_influxdb ;;
        21) uninstall_grafana ;;
        22) uninstall_ignition ;;
        23) uninstall_bitwarden_cli ;;
        24) run_all_reset_tasks ;;
        x|X) printf "Exiting...\n"; exit 0 ;;
        *) clear; continue ;;
    esac
    printf "\nPress enter to go back to the menu: "
    read -r
    clear
done
