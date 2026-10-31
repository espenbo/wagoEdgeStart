#!/bin/bash

# Install programs on a WAGO Edge Computer. Run it as a normal user, it uses sudo where it is needed.

normal=`echo "\033[m"`
menu=`echo "\033[36m"` #blue
number=`echo "\033[33m"` #yellow
fgred=`echo "\033[31m"`
fggreen=`echo "\033[32m"`

GITHUB_RAW="https://raw.githubusercontent.com/espenbo/wagoEdgeStart/main"

# Run as a normal user with sudo rights
check_user() {
    if [ "$EUID" -eq 0 ]; then
        printf "${fgred}Please run this as a normal user, without sudo. It asks for sudo when it is needed.${normal}\n"
        echo "No normal user yet? Create one with:  adduser NAME  and  usermod -aG sudo NAME"
        exit 1
    fi
    if ! command -v sudo &>/dev/null; then
        printf "${fgred}sudo is not installed.${normal} Log in as root and run:\n"
        echo "  apt install -y sudo && usermod -aG sudo $USER"
        echo "Then log out and in again."
        exit 1
    fi
    echo "You may be asked for your sudo password."
    if ! sudo -v; then
        printf "${fgred}Your user needs sudo rights.${normal} As root, run:  usermod -aG sudo $USER\n"
        exit 1
    fi
}

# Print [installed] after a menu line when the command, or the Docker container, exists.
# A normal user has no sbin in PATH.
installed() {
    if PATH="$PATH:/usr/sbin:/sbin:/snap/bin" command -v "$1" &>/dev/null || grep -qx "${2:-none}" <<< "$DOCKER_NAMES"; then
        printf "${fggreen}[installed]${normal}"
    fi
}

menu_line() {
    printf "${menu} ${number}%3s)${menu} %s ${normal}%b\n" "$1" "$2" "$3"
}

# Display all tasks, grouped
show_menu(){
    DOCKER_NAMES="$(docker ps -a --format '{{.Names}}' 2>/dev/null)"
    printf "\n${menu}********* WAGO Edge Setup ***********${normal}\n"
    menu_line 1 "Recommended setup. Explains and asks before each step"
    printf "\n${menu} System${normal}\n"
    menu_line 2 "Update the system"
    menu_line 3 "Common tools (htop, tmux, curl, rsync, mbpoll ...)"
    menu_line 4 "WAGO login script"
    menu_line 5 "Automatic security updates"
    printf "\n${menu} Network and remote access${normal}\n"
    menu_line 6 "Firewall (UFW)" "$(installed ufw)"
    menu_line 7 "Cockpit, web manager on port 9090" "$(installed cockpit-bridge)"
    menu_line 8 "Tailscale, secure remote access" "$(installed tailscale)"
    menu_line 9 "Fail2ban, blocks SSH password guessing" "$(installed fail2ban-client)"
    menu_line 10 "File server (Samba), share files with other machines" "$(installed smbd)"
    menu_line 11 "Join a Windows domain (realm)" "$(installed realm)"
    printf "\n${menu} Docker${normal}\n"
    menu_line 12 "Docker and Docker Compose" "$(installed docker)"
    menu_line 13 "LazyDocker, Docker in the terminal" "$(installed lazydocker lazydocker)"
    menu_line 14 "Portainer, Docker in the browser" "$(installed none portainer)"
    printf "\n${menu} Automation${normal}\n"
    menu_line 15 "Node-RED" "$(installed node-red)"
    menu_line 16 "Node.js" "$(installed node)"
    menu_line 17 "Java" "$(installed java)"
    menu_line 18 "OPC UA Commander, OPC UA client" "$(installed opcua-commander)"
    menu_line 19 "opcilloscope, OPC UA client" "$(installed opcilloscope)"
    menu_line 20 "Mosquitto, MQTT broker" "$(installed mosquitto)"
    menu_line 21 "EKBPRO KNX Terminal and KNX project" "$(installed ~/ekbpro-knx-terminal-python/scada)"
    printf "\n${menu} Data and SCADA${normal}\n"
    menu_line 22 "InfluxDB, database for measurements" "$(installed influxd influxdb)"
    menu_line 23 "Grafana, dashboards" "$(installed grafana-server grafana)"
    menu_line 24 "Ignition, SCADA platform" "$(installed /usr/local/bin/ignition/ignition.sh ignition)"
    printf "\n${menu} Passwords${normal}\n"
    menu_line 25 "Bitwarden CLI, passwords in the terminal" "$(installed bw)"
    echo
    menu_line i "Read about all programs"
    menu_line x "Exit"
    printf "Pick a number to read about a program and choose if you want it: "
    read -r opt || exit 0
}

# Print one heading with wrapped text under it
about_part() {
    printf "${number}%s${normal}\n" "$1"
    printf '%s\n' "$2" | fold -s -w 74 | sed 's/^/  /'
}

# Print what a program does, why you want it, and an optional note
about() {
    about_part "What it does" "$1"
    about_part "Why use it" "$2"
    if [ -n "$3" ]; then
        about_part "Good to know" "$3"
    fi
}

# The description of a menu option
describe() {
    case $1 in
        2) about "Downloads and installs the latest versions of everything installed with apt." \
            "Closes security holes and fixes errors. Always do this first on a new machine." \
            "Can take several minutes. Some updates need a reboot." ;;
        3) about "Installs tools for the terminal: htop (what uses CPU and memory), tmux (keeps work running if SSH drops), ncdu (what fills the disk), mc (file manager), vim, rsync (copy files), curl, dnsutils, net-tools, bmon and iperf3 (network tests), mbpoll (read and write Modbus), lm-sensors (temperatures) and support for exFAT and NTFS disks." \
            "You will want these when something has to be fixed or tested on the machine." ;;
        4) about "Shows a WAGO welcome screen with information about the machine when you log in." \
            "You see right away which machine you are on and how it is doing." ;;
        5) about "Installs security updates by itself every day, with unattended-upgrades." \
            "An edge computer often runs for years without anyone logging in. This keeps it protected." \
            "The machine is not rebooted automatically." ;;
        6) about "Blocks all incoming connections except the ports you choose. UFW is a simple front end to the Linux firewall." \
            "Programs that are not meant for the network cannot be reached by accident." \
            "SSH always stays open. Ports published by Docker containers go past UFW." ;;
        7) about "A web page for managing the machine: services, logs, disks, updates, users and a terminal." \
            "You can look after the machine from a browser, without knowing Linux commands." \
            "Opens on port 9090. Log in with your Linux user." ;;
        8) about "Connects your machines in a private encrypted network that works through routers and firewalls." \
            "Reach the machine from anywhere, without opening ports or setting up a VPN server." \
            "Needs a Tailscale account, which is free for small networks." ;;
        9) about "Watches SSH logins and blocks an address for 10 minutes after 5 failed attempts." \
            "Stops password guessing, which is common on machines reachable from the internet." \
            "You can block yourself for 10 minutes by typing the wrong password too many times." ;;
        10) about "Shares a folder over the network with Samba, like a shared folder in Windows." \
            "Other machines can get log files, reports and programs without USB sticks or FTP." \
            "You choose the folder, and whether a password is needed. This works without a domain." ;;
        11) about "Connects the machine to a Windows domain (Active Directory), so domain users can log in to it." \
            "On a larger network, users and passwords are managed in one place." \
            "Needs a domain and a domain admin user. This does not share files, that is option 10." ;;
        12) about "Docker runs programs in containers, separate from each other and the rest of the system. Docker Compose starts several containers from one file." \
            "Programs are easy to install, update and remove, and they do not disturb each other." \
            "Log out and in again after the install." ;;
        13) about "Shows containers, logs and resource use in the terminal, and lets you restart them with a key." \
            "Quicker than typing docker commands, and it works over SSH." ;;
        14) about "A web page for managing containers, images and volumes on port 9443." \
            "Good if you prefer a browser, or if more people look after the machine." \
            "Needs Docker. Create the admin user within 5 minutes." ;;
        15) about "Build logic by connecting boxes in a browser, with ready support for Modbus, OPC UA, MQTT and much more." \
            "The quickest way to move data between machines, databases and web pages, without much programming." \
            "Opens on port 1880. Set a password in the installer." ;;
        16) about "Runs programs written in JavaScript." \
            "Needed by OPC UA Commander and other tools. Node-RED brings its own, so you can skip this for Node-RED." ;;
        17) about "Runs programs written in Java." \
            "Only needed if a program you use asks for it." ;;
        18) about "Browse and read values from an OPC UA server in the terminal." \
            "Check that a PLC or server answers, directly on the machine and without a PC." ;;
        19) about "A light OPC UA client for the terminal that also shows values over time." \
            "An alternative to OPC UA Commander when you want to follow how values change." ;;
        20) about "A message broker for MQTT: machines publish values to a topic, and others subscribe to it." \
            "The usual way to send data between sensors, Node-RED, databases and cloud services." \
            "Only answers on this machine until you configure users." ;;
        21) about "A SCADA for KNX buildings in the terminal, with rooms, alarms, trends and floor plan, built from your ETS project." \
            "See and operate a KNX installation over SSH, with no web server or license." \
            "Have the ETS project ready. You are guided through the setup." ;;
        22) about "A database made for measurements over time, like temperatures and energy use." \
            "Keep history from machines and meters. Ordinary databases handle this kind of data poorly." \
            "Fills the disk over time, so set how long data is kept." ;;
        23) about "Makes dashboards and charts in a browser from InfluxDB and other sources, and can send alarms." \
            "Often used with InfluxDB to see trends, on screens or from your phone." \
            "Opens on port 3000. Change the password at first login." ;;
        24) about "A complete SCADA platform with HMI, alarms, history and reports, from Inductive Automation." \
            "For larger projects that need many screens and users, with drivers for most PLCs." \
            "Commercial. Without a license it is a trial that stops every 2 hours. Uses much more memory than the other programs here." ;;
        25) about "The official Bitwarden client for the terminal. It connects this machine to your Bitwarden account, or to your own Bitwarden server." \
            "Look up passwords over SSH without a browser, and let your own scripts fetch passwords instead of storing them in files." \
            "Needs a Bitwarden account. No port is opened. A copy of the vault is kept encrypted in your home folder." ;;
    esac
}

# Read about all programs, one screen at a time
show_all_descriptions() {
    local option
    for option in {2..25}; do
        printf "\n${menu}Option %s${normal}\n" "$option"
        describe "$option"
    done | less -R
}

# Ask with a default answer, enter gives the default
ask_yes() {
    printf "${menu}%s (yes/no) ${number}[%s]${menu}: ${normal}" "$1" "$2"
    read -r answer
    answer="${answer:-$2}"
    [[ "$answer" == "yes" || "$answer" == "y" ]]
}

# Ask for a text with a default answer. The answer ends up in ANSWER.
ask_text() {
    printf "${menu}%s ${number}[%s]${menu}: ${normal}" "$1" "$2"
    read -r ANSWER
    ANSWER="${ANSWER:-$2}"
}

# Choose how to install: choose_method "question" "first option" "second option" ...
# The number ends up in METHOD. It returns 1 when the user cancels.
choose_method() {
    local number_of=1 option
    printf "${menu}%s${normal}\n" "$1"
    shift
    for option in "$@"; do
        menu_line "$number_of" "$option"
        number_of=$((number_of + 1))
    done
    menu_line x "Cancel"
    ask_text "Please enter your choice" "1"
    METHOD="$ANSWER"
    [[ "$METHOD" =~ ^[0-9]+$ ]] && [ "$METHOD" -ge 1 ] && [ "$METHOD" -le "$#" ]
}

# Open a port if the firewall is running
open_firewall() {
    if sudo ufw status 2>/dev/null | grep -q "Status: active"; then
        sudo ufw allow "$1"
    fi
}

this_ip() {
    hostname -I | awk '{print $1}'
}

ensure_curl() {
    if ! command -v curl &>/dev/null; then
        echo "Installing curl..."
        sudo apt-get install -y curl
    fi
}

# Add a line to a shell profile, once
add_to_bashrc() {
    grep -qxF "$1" ~/.bashrc 2>/dev/null || echo "$1" >> ~/.bashrc
}

# Programs installed with nvm are only found after this
load_nvm() {
    if [ -s "$HOME/.nvm/nvm.sh" ]; then
        . "$HOME/.nvm/nvm.sh"
    fi
}

# Global npm packages need sudo, except with nvm where they live in the home folder
npm_global() {
    if [[ "$(command -v npm)" == "$HOME"/* ]]; then
        npm "$@"
    else
        sudo npm "$@"
    fi
}

need_docker() {
    if ! command -v docker &>/dev/null; then
        ask_yes "This needs Docker. Install Docker first?" "yes" || return 1
        install_docker || return 1
    fi
}

# Start a container that restarts with the machine, unless it exists: run_container name docker-run-arguments...
run_container() {
    local name="$1"
    shift
    if sudo docker ps -a --format '{{.Names}}' | grep -qx "$name"; then
        echo "The container $name already exists."
        return 0
    fi
    sudo docker run -d --name "$name" --restart=always "$@"
}

# Run one task and remember how it went
RESULTS=()
run_task() {
    local title="$1"
    shift
    printf "\n${menu}=== %s ===${normal}\n" "$title"
    if "$@"; then
        RESULTS+=("${fggreen}done  ${normal} $title")
    else
        RESULTS+=("${fgred}FAILED${normal} $title")
    fi
}

# Explain an option and ask before running it: offer_task option "title" function
offer_task() {
    printf "\n${menu}%s${normal}\n" "$2"
    describe "$1"
    echo
    if ask_yes "Continue?" "yes"; then
        run_task "$2" "$3"
    else
        RESULTS+=("skipped $2")
    fi
}

show_results() {
    local line
    printf "\n${menu}********* Result ***********${normal}\n"
    for line in "${RESULTS[@]}"; do
        printf "%b\n" "$line"
    done
    RESULTS=()
}

# Update package list and upgrade system
update_system() {
    sudo apt-get update && sudo apt-get upgrade -y
}

# Install java default-jre default-jdk
install_java() {
    sudo apt-get install -y default-jre default-jdk
}

# Install Tailscale
install_tailscale() {
    ensure_curl
    # Tailscale needs /dev/net/tun, which an LXC container does not have by default
    if [ "$(systemd-detect-virt -c 2>/dev/null)" = "lxc" ]; then
        printf "${fgred}This is an LXC container.${normal} Add this to the config on the host, for example /etc/pve/lxc/112.conf:\n"
        echo "  lxc.cgroup2.devices.allow: c 10:200 rwm"
        echo "  lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file"
        echo "See https://tailscale.com/kb/1130/lxc-unprivileged"
        ask_yes "Continue the install?" "yes" || return 0
    fi
    curl -fsSL https://tailscale.com/install.sh | sh || return 1
    echo "Follow the link below to connect this machine to your Tailscale account."
    sudo tailscale up
}

# All ports SSH can be reached on, the firewall must never lock them out.
# This connection counts too, and 22 is the fallback.
ssh_ports() {
    {
        sudo sshd -T 2>/dev/null | awk '$1 == "port" {print $2}'
        sudo ss -tlnpH 2>/dev/null | awk '/sshd/ {n = split($4, a, ":"); print a[n]}'
        echo "$SSH_CONNECTION" | awk 'NF == 4 {print $4}'
    } | sort -un | grep . || echo 22
}

# Answer yes for a program that is installed, so the firewall follows what is on the machine
yes_if_installed() {
    if [ -n "$(installed "$@")" ]; then
        echo yes
    else
        echo no
    fi
}

# Allow ports in the firewall after asking: allow_ports "description" default port...
allow_ports() {
    local title="$1" default="$2" port
    shift 2
    if ask_yes "Open $title ($*)?" "$default"; then
        for port in "$@"; do
            sudo ufw allow "$port"
        done
    fi
}

# Install UFW and set it up
install_ufw() {
    sudo apt-get install -y ufw || return 1
    if sudo ufw status | grep -q "Status: active" && \
        ask_yes "The firewall is active. Delete the existing rules and start over?" "no"; then
        sudo ufw --force reset
    fi

    # SSH goes first, so it is open before anything is closed
    local port
    for port in $(ssh_ports); do
        echo "Allowing SSH on port $port, so you are not locked out..."
        sudo ufw allow "$port/tcp"
    done
    sudo ufw default deny incoming
    sudo ufw default allow outgoing

    allow_ports "web pages" "yes" 80/tcp 443/tcp
    allow_ports "Cockpit" "$(yes_if_installed cockpit-bridge)" 9090/tcp
    allow_ports "Node-RED" "$(yes_if_installed node-red)" 1880/tcp
    allow_ports "Modbus TCP" "yes" 502/tcp
    allow_ports "OPC UA" "yes" 4840/tcp 4843/tcp
    allow_ports "file sharing (Samba)" "$(yes_if_installed smbd)" 139/tcp 445/tcp
    allow_ports "MQTT, only if other machines use the broker" "no" 1883/tcp
    allow_ports "InfluxDB" "$(yes_if_installed influxd)" 8086/tcp
    allow_ports "Grafana" "$(yes_if_installed grafana-server)" 3000/tcp
    allow_ports "Ignition" "$(yes_if_installed /usr/local/bin/ignition/ignition.sh)" 8088/tcp 8043/tcp
    allow_ports "KNX routing, not needed for tunneling" "no" 3671/udp
    allow_ports "OPC UA test servers" "no" 62540/tcp 62541/tcp 62546/tcp 62547/tcp 61210/tcp 61211/tcp

    sudo ufw --force enable || return 1
    sudo ufw status verbose
    if command -v docker &>/dev/null; then
        printf "${fgred}Note:${normal} these Docker ports go past UFW and are open whatever the firewall says:\n"
        sudo docker ps --format '  {{.Names}}: {{.Ports}}'
    fi
}

# Let NetworkManager take over the network, for the network page in Cockpit
use_network_manager() {
    local interfaces="/etc/network/interfaces"
    if grep -rqE '^\s*iface\s+\S+\s+inet6?\s+static' "$interfaces" /etc/network/interfaces.d 2>/dev/null; then
        printf "${fgred}This machine has a fixed IP address in %s. Nothing was changed.${normal}\n" "$interfaces"
        echo "Moving it could cut your connection. Do this at the machine, with a screen and keyboard."
        return 0
    fi
    printf "${fgred}The network restarts now. The IP address can change and SSH can disconnect.${normal}\n"
    ask_yes "Continue?" "no" || return 0
    sudo cp "$interfaces" "$interfaces.bak"
    echo "Backup saved as $interfaces.bak"
    sudo sed -i -E '/^(auto|allow-hotplug|iface)\s+lo\b/! s/^(auto|allow-hotplug|iface)\b/#&/' "$interfaces"
    sudo systemctl restart NetworkManager
}

# Install Cockpit
install_cockpit() {
    sudo apt-get install -y cockpit cockpit-bridge cockpit-networkmanager cockpit-packagekit cockpit-pcp cockpit-storaged cockpit-system cockpit-ws || return 1
    sudo systemctl enable --now cockpit.socket || return 1
    open_firewall 9090/tcp

    echo
    echo "The network page in Cockpit only works with NetworkManager. Everything else works without it."
    if ask_yes "Let NetworkManager take over the network?" "no"; then
        use_network_manager
    fi

    printf "Cockpit: ${number}https://%s:9090/${normal}\n" "$(this_ip)"
    echo "Log in with your normal Linux user."
}

# Install Docker and Docker Compose
install_docker() {
    local id codename
    id="$(. /etc/os-release && echo "$ID")"
    codename="$(. /etc/os-release && echo "$VERSION_CODENAME")"
    sudo apt-get remove -y docker docker-engine docker.io containerd runc
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg || return 1
    curl -fsSL "https://download.docker.com/linux/$id/gpg" | sudo gpg --dearmor --yes -o /usr/share/keyrings/docker-archive-keyring.gpg || return 1
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/$id $codename stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin || return 1
    sudo systemctl enable --now docker || return 1
    if ! id -nG "$USER" | grep -qw docker; then
        sudo usermod -aG docker "$USER"
        echo "Log out and in again to use docker without sudo."
    fi
}

# Install LazyDocker
install_lazydocker() {
    local docker_command="docker run --rm -it -v /var/run/docker.sock:/var/run/docker.sock -v $HOME/.config/lazydocker:/.config/jesseduffield/lazydocker lazyteam/lazydocker"
    choose_method "How do you want to install LazyDocker?" \
        "Download the program (recommended). Starts fast, works on all machines" \
        "Run it in Docker. Nothing is installed outside Docker, amd64 machines only" || return 0
    ensure_curl
    sed -i '/^alias lzd=/d' ~/.bashrc
    case "$METHOD" in
        1)
            curl -fsSL https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh | bash || return 1
            add_to_bashrc 'export PATH="$PATH:$HOME/.local/bin"'
            add_to_bashrc "alias lzd='$HOME/.local/bin/lazydocker'"
            export PATH="$PATH:$HOME/.local/bin"
            ;;
        2)
            need_docker || return 1
            sudo docker pull lazyteam/lazydocker || return 1
            add_to_bashrc "alias lzd='$docker_command'"
            ;;
    esac
    echo "Log out and in again, then start it with: lzd"
    echo "Keys: https://github.com/jesseduffield/lazydocker/tree/master/docs/keybindings"
}

# Install Portainer
install_portainer() {
    need_docker || return 0
    sudo docker volume create portainer_data || return 1
    run_container portainer -p 9443:9443 \
        -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data \
        portainer/portainer-ce:lts || return 1
    printf "Portainer: ${number}https://%s:9443/${normal}\n" "$(this_ip)"
    echo "Open it within 5 minutes and create the admin user, otherwise restart it with: sudo docker restart portainer"
}

# Install other necessary programs
install_other_programs() {
    sudo apt-get install -y sudo appstream bmon curl dnsutils exfat-fuse gnupg gpg-agent gpgconf htop iperf3 lm-sensors mbpoll mc ncdu net-tools nfs-common ntfs-3g rsync rsyslog tmux vim
}

# Install WAGO login script
install_wago_login() {
    ensure_curl
    if [ -f /etc/WAGO_LOGIN ]; then
        sudo cp /etc/WAGO_LOGIN /etc/WAGO_LOGIN.old
        echo "Old file copied to /etc/WAGO_LOGIN.old"
    fi
    sudo curl -fsSL -o /etc/WAGO_LOGIN "$GITHUB_RAW/WagoLogin/WAGO_LOGIN" || return 1
    sudo chown root:root /etc/WAGO_LOGIN
    sudo chmod 755 /etc/WAGO_LOGIN
    if ! grep -q "/etc/WAGO_LOGIN" /etc/profile; then
        sudo sed -i '/export PATH/a /etc/WAGO_LOGIN' /etc/profile
    fi
    echo "The login script is shown the next time you log in."
}

# Share a folder with other machines
install_file_server() {
    local share folder smb_conf="/etc/samba/smb.conf"
    echo "Other machines can open the folder over the network, like a shared folder in Windows."
    ask_text "Name of the share, without spaces" "share"
    share="$ANSWER"
    if [[ ! "$share" =~ ^[A-Za-z0-9_-]+$ ]]; then
        echo "Use only letters, numbers, - and _ in the name."
        return 1
    fi
    ask_text "Folder to share" "/srv/$share"
    folder="$ANSWER"
    if [[ ! "$folder" =~ ^/(srv|mnt|media|data|home)/[A-Za-z0-9._/-]+$ ]]; then
        echo "Use a folder under /srv, /mnt, /media, /data or /home, without spaces."
        return 1
    fi
    choose_method "Who can open the share?" \
        "Users with a password (recommended)" \
        "Everyone on the network, without a password. Everything in the folder can be read and changed" || return 0

    sudo apt-get install -y samba || return 1
    sudo mkdir -p "$folder" || return 1
    sudo chown "$USER:sambashare" "$folder"
    sudo chmod 2775 "$folder"

    if grep -q "^\[$share\]" "$smb_conf"; then
        echo "The share $share already exists in $smb_conf."
    else
        sudo cp "$smb_conf" "$smb_conf.bak"
        if [ "$METHOD" = "1" ]; then
            printf '\n[%s]\n   path = %s\n   read only = no\n   valid users = @sambashare\n   create mask = 0664\n   directory mask = 2775\n' \
                "$share" "$folder" | sudo tee -a "$smb_conf" > /dev/null
        else
            printf '\n[%s]\n   path = %s\n   read only = no\n   guest ok = yes\n   force user = %s\n   create mask = 0664\n   directory mask = 2775\n' \
                "$share" "$folder" "$USER" | sudo tee -a "$smb_conf" > /dev/null
        fi
    fi
    if ! sudo testparm -s &>/dev/null; then
        echo "The Samba configuration has an error, the old one is restored."
        sudo cp "$smb_conf.bak" "$smb_conf"
        return 1
    fi

    if [ "$METHOD" = "1" ]; then
        sudo usermod -aG sambashare "$USER"
        echo "Choose the password that is used to open the share, as user $USER."
        sudo smbpasswd -a "$USER" || return 1
        echo "More users: sudo adduser NAME && sudo usermod -aG sambashare NAME && sudo smbpasswd -a NAME"
    fi
    sudo systemctl enable smbd nmbd
    sudo systemctl restart smbd nmbd || return 1
    open_firewall 139/tcp
    open_firewall 445/tcp
    printf "In Windows, open: ${number}\\\\\\\\%s\\\\%s${normal}\n" "$(this_ip)" "$share"
    printf "On Linux, open:   ${number}smb://%s/%s${normal}\n" "$(this_ip)" "$share"
}

# Join a Windows domain
join_domain() {
    local domain admin
    printf "${menu}Domain name, for example firma.local. Empty to cancel: ${normal}"
    read -r domain
    [ -n "$domain" ] || return 0
    sudo apt-get install -y realmd sssd sssd-tools libnss-sss libpam-sss adcli samba-common-bin oddjob oddjob-mkhomedir packagekit || return 1
    sudo realm discover "$domain" || return 1
    printf "${menu}Domain admin user: ${normal}"
    read -r admin
    sudo realm join -U "$admin" "$domain" || return 1
    sudo pam-auth-update --enable mkhomedir
}

# Install OPC UA Commander
install_opcua_commander() {
    choose_method "How do you want to install OPC UA Commander?" \
        "NPM (recommended). Needs Node.js, simple to update" \
        "Snap. Separate from the rest of the system, updates by itself, uses more disk" \
        "Docker. Separate from the rest of the system, builds an image on this machine" || return 0
    case "$METHOD" in
        1)
            if ! command -v npm &>/dev/null; then
                install_nodejs || return 1
            fi
            npm_global install -g opcua-commander || return 1
            echo "Start it with: opcua-commander -e opc.tcp://localhost:4840"
            ;;
        2)
            sudo apt-get install -y snapd || return 1
            sudo snap install core || return 1
            sudo snap install opcua-commander || return 1
            echo "Log out and in again, then start it with: opcua-commander -e opc.tcp://localhost:4840"
            ;;
        3)
            need_docker || return 1
            sudo docker build -t commander https://github.com/node-opcua/opcua-commander.git || return 1
            add_to_bashrc "alias opcua-commander='docker run -it --rm --network host commander'"
            echo "Log out and in again, then start it with: opcua-commander -e opc.tcp://localhost:4840"
            ;;
    esac
}

# Install opcilloscope
install_opcilloscope() {
    ensure_curl
    echo "Provided by https://github.com/SquareWaveSystems/opcilloscope"
    curl -fsSL https://raw.githubusercontent.com/SquareWaveSystems/opcilloscope/main/install.sh | bash || return 1
    add_to_bashrc 'export PATH="$PATH:$HOME/.local/bin"'
    export PATH="$PATH:$HOME/.local/bin"
}

# Install Node.js
install_nodejs() {
    if command -v node &>/dev/null; then
        echo "Node.js $(node -v) is already installed."
        return 0
    fi
    choose_method "How do you want to install Node.js?" \
        "NodeSource (recommended). New version, updated with the rest of the system" \
        "Debian. Simplest and stable, but an older version" \
        "NVM. Several versions side by side, for this user only" || return 0
    ensure_curl
    case "$METHOD" in
        1)
            ask_text "Node.js version" "24"
            sudo apt-get install -y ca-certificates gnupg || return 1
            curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | sudo gpg --dearmor --yes -o /usr/share/keyrings/nodesource.gpg || return 1
            echo "deb [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$ANSWER.x nodistro main" | sudo tee /etc/apt/sources.list.d/nodesource.list > /dev/null
            sudo apt-get update
            sudo apt-get install -y nodejs || return 1
            ;;
        2)
            sudo apt-get install -y nodejs npm || return 1
            ;;
        3)
            curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash || return 1
            load_nvm
            nvm install --lts || return 1
            ;;
    esac
    node -v
}

# Install Node-RED with the official installer, which also installs Node.js
install_nodered() {
    ensure_curl
    echo "The official Node-RED installer starts now and asks a few questions."
    sudo apt-get install -y build-essential || return 1
    bash <(curl -fsSL https://raw.githubusercontent.com/node-red/linux-installers/master/deb/update-nodejs-and-nodered) || return 1
    open_firewall 1880/tcp
    printf "Node-RED: ${number}http://%s:1880/${normal}\n" "$(this_ip)"
}

# Install InfluxDB
install_influxdb() {
    choose_method "Which InfluxDB do you want?" \
        "InfluxDB 2 as a service (recommended). Has web pages on port 8086, works with Node-RED and Grafana" \
        "InfluxDB 2 in Docker. The same, separate from the rest of the system" \
        "InfluxDB 3 Core in Docker. Newest generation, port 8181, no web pages" || return 0
    ensure_curl
    case "$METHOD" in
        1)
            sudo apt-get install -y ca-certificates gnupg || return 1
            curl -fsSL https://repos.influxdata.com/influxdata-archive.key | sudo gpg --dearmor --yes -o /usr/share/keyrings/influxdata-archive.gpg || return 1
            echo "deb [signed-by=/usr/share/keyrings/influxdata-archive.gpg] https://repos.influxdata.com/debian stable main" | sudo tee /etc/apt/sources.list.d/influxdata.list > /dev/null
            sudo apt-get update
            sudo apt-get install -y influxdb2 || return 1
            sudo systemctl enable --now influxdb || return 1
            open_firewall 8086/tcp
            ;;
        2)
            need_docker || return 1
            run_container influxdb -p 8086:8086 \
                -v influxdb2_data:/var/lib/influxdb2 -v influxdb2_config:/etc/influxdb2 influxdb:2 || return 1
            ;;
        3)
            need_docker || return 1
            run_container influxdb -p 8181:8181 -v influxdb3_data:/var/lib/influxdb3/data influxdb:3-core \
                influxdb3 serve --node-id=edge --object-store=file --data-dir=/var/lib/influxdb3/data || return 1
            echo "Create a token with: sudo docker exec -it influxdb influxdb3 create token --admin"
            echo "Getting started: https://docs.influxdata.com/influxdb3/core/get-started/"
            return 0
            ;;
    esac
    printf "InfluxDB: ${number}http://%s:8086/${normal}\n" "$(this_ip)"
    echo "Open it and create the first user. Set a retention period on your buckets, so the disk does not fill up."
}

# Install Grafana
install_grafana() {
    choose_method "How do you want to install Grafana?" \
        "As a service (recommended). Updated with the rest of the system" \
        "Docker. Separate from the rest of the system" || return 0
    ensure_curl
    case "$METHOD" in
        1)
            sudo apt-get install -y ca-certificates gnupg || return 1
            curl -fsSL https://apt.grafana.com/gpg.key | sudo gpg --dearmor --yes -o /usr/share/keyrings/grafana.gpg || return 1
            echo "deb [signed-by=/usr/share/keyrings/grafana.gpg] https://apt.grafana.com stable main" | sudo tee /etc/apt/sources.list.d/grafana.list > /dev/null
            sudo apt-get update
            sudo apt-get install -y grafana || return 1
            sudo systemctl enable --now grafana-server || return 1
            open_firewall 3000/tcp
            ;;
        2)
            need_docker || return 1
            run_container grafana -p 3000:3000 -v grafana_data:/var/lib/grafana grafana/grafana-oss || return 1
            ;;
    esac
    printf "Grafana: ${number}http://%s:3000/${normal}\n" "$(this_ip)"
    echo "Log in with admin / admin and choose a new password right away."
}

# Install Ignition. The license is accepted by you, on the first page in the browser or in the installer.
install_ignition() {
    local installer
    echo "Ignition is commercial software from Inductive Automation. Without a license it runs as a"
    echo "trial that stops every 2 hours until you reset it."
    echo "License: https://inductiveautomation.com/ignition/license"
    choose_method "How do you want to install Ignition?" \
        "Docker (recommended). Simple to update and to remove" \
        "Installer from Inductive Automation, as a service. You download it yourself, 64-bit Intel or AMD only" || return 0
    case "$METHOD" in
        1)
            need_docker || return 1
            run_container ignition -p 8088:8088 -p 8043:8043 -v ignition_data:/usr/local/bin/ignition/data \
                inductiveautomation/ignition:latest -n "$(hostname)" -h 8088 -s 8043 || return 1
            ;;
        2)
            if [ "$(dpkg --print-architecture)" != "amd64" ]; then
                echo "The installer does not run on this machine, use Docker."
                return 1
            fi
            # The download server does not accept scripts, so the file comes from a browser
            echo "1. Download the Linux 64-bit installer in a browser: https://inductiveautomation.com/downloads/"
            echo "2. Copy it to this machine, from your own PC:"
            printf "${number}   scp ignition-*-linux-64-installer.run %s@%s:~/${normal}\n" "$USER" "$(this_ip)"
            ask_text "3. Path to the installer on this machine" "$(ls -t "$HOME"/ignition-*-linux-64-installer.run 2>/dev/null | head -n 1)"
            installer="$ANSWER"
            if [ ! -f "$installer" ]; then
                echo "Could not find the installer, nothing was installed."
                return 1
            fi
            chmod +x "$installer"
            sudo "$installer" || return 1
            open_firewall 8088/tcp
            open_firewall 8043/tcp
            ;;
    esac
    printf "Ignition: ${number}http://%s:8088/${normal}\n" "$(this_ip)"
    echo "Open it to accept the license and create the admin user. Startup can take a few minutes."
}

# Download the Bitwarden CLI. The address of the newest version comes from Bitwarden's download link.
download_bitwarden_cli() {
    local url folder result=0
    sudo apt-get install -y unzip || return 1
    url="$(curl -fsSI -o /dev/null -w '%{redirect_url}' 'https://vault.bitwarden.com/download/?app=cli&platform=linux')"
    if [ -z "$url" ]; then
        echo "Could not find the download address."
        return 1
    fi
    case "$(dpkg --print-architecture)" in
        amd64) ;;
        arm64) url="${url/bw-linux-/bw-linux-arm64-}" ;;
        *)
            echo "There is no download for this machine, try NPM."
            return 1
            ;;
    esac
    folder="$(mktemp -d)"
    curl -fsSL -o "$folder/bw.zip" "$url" && unzip -q "$folder/bw.zip" -d "$folder" \
        && sudo install -m 755 "$folder/bw" /usr/local/bin/bw || result=1
    rm -rf "$folder"
    return "$result"
}

# Install the Bitwarden CLI
install_bitwarden_cli() {
    choose_method "How do you want to install the Bitwarden CLI?" \
        "Download the program (recommended). Works on amd64 and arm64, update by running this option again" \
        "NPM. Needs Node.js 22 or newer, simple to update" \
        "Snap. Updates by itself, amd64 machines only, uses more disk" || return 0
    ensure_curl
    case "$METHOD" in
        1)
            download_bitwarden_cli || return 1
            ;;
        2)
            if ! command -v npm &>/dev/null; then
                install_nodejs || return 1
            fi
            if [ "$(node -p 'process.versions.node.split(".")[0]')" -lt 22 ]; then
                echo "The Bitwarden CLI needs Node.js 22 or newer. Install a newer version with option 16."
                return 1
            fi
            npm_global install -g @bitwarden/cli || return 1
            ;;
        3)
            sudo apt-get install -y snapd || return 1
            sudo snap install core || return 1
            sudo snap install bw || return 1
            ;;
    esac
    echo "Log out and in again if bw is not found. Then:"
    echo "  bw config server https://your-server    only if you run your own Bitwarden server"
    echo "  bw login                                log in to your account"
    echo "  export BW_SESSION=\"\$(bw unlock --raw)\"   unlock the vault in this terminal"
    echo "  bw get password NAME                    fetch a password"
    echo "Run 'bw lock' when you are done."
}

# Install Mosquitto
install_mosquitto() {
    sudo apt-get install -y mosquitto mosquitto-clients || return 1
    sudo systemctl enable --now mosquitto || return 1
    echo "Mosquitto answers on this machine only, which suits Node-RED and other local programs."
    echo "Other machines need a listener and users in /etc/mosquitto/conf.d/, and port 1883 in the firewall."
}

# Install Fail2ban, reading the SSH log from the systemd journal
install_fail2ban() {
    sudo apt-get install -y fail2ban python3-systemd || return 1
    printf '[sshd]\nenabled = true\nbackend = systemd\n' | sudo tee /etc/fail2ban/jail.d/sshd-systemd.conf > /dev/null
    sudo systemctl enable fail2ban || return 1
    sudo systemctl restart fail2ban || return 1
    echo "An address is blocked for 10 minutes after 5 failed SSH logins."
}

# Install unattended-upgrades
install_unattended_upgrades() {
    local config_file="/etc/apt/apt.conf.d/50unattended-upgrades" email_address
    sudo apt-get install -y unattended-upgrades || return 1
    sudo cp "$config_file" "$config_file.bak"
    echo "Backup of the configuration created at $config_file.bak"

    # Enable normal and security updates, and remove unused dependencies
    sudo sed -i 's#//\("\o.*-updates";\)#\1#' "$config_file"
    sudo sed -i 's#//\("\o.*label=Debian";\)#\1#' "$config_file"
    sudo sed -i 's#//\("\o.*label=Debian-Security";\)#\1#' "$config_file"
    sudo sed -i 's#//Unattended-Upgrade::Remove-Unused-Dependencies.*#Unattended-Upgrade::Remove-Unused-Dependencies "true";#' "$config_file"

    if ask_yes "Send an email about updates? This needs a mail program on the machine." "no"; then
        printf "${menu}Email address: ${normal}"
        read -r email_address
        sudo sed -i "s#//Unattended-Upgrade::Mail.*#Unattended-Upgrade::Mail \"$email_address\";#" "$config_file"
    fi

    echo "unattended-upgrades unattended-upgrades/enable_auto_upgrades boolean true" | sudo debconf-set-selections
    sudo dpkg-reconfigure -f noninteractive unattended-upgrades
}

# Install EKBPRO KNX Terminal. The installer asks for the KNX project and sets up the program
install_knx_terminal() {
    local script_dir knx_installer status
    script_dir="$(cd "$(dirname "$0")" && pwd)"
    if [ -f "$script_dir/install_knx_terminal.sh" ]; then
        bash "$script_dir/install_knx_terminal.sh"
        return
    fi

    echo "Downloading the KNX installer from GitHub..."
    ensure_curl
    knx_installer="$(mktemp)"
    if ! curl -fsSL -o "$knx_installer" "$GITHUB_RAW/setupEdgeComputer/install_knx_terminal.sh"; then
        echo "Could not download the KNX installer."
        rm -f "$knx_installer"
        return 1
    fi
    bash "$knx_installer"
    status=$?
    rm -f "$knx_installer"
    return $status
}

recommended_setup() {
    echo "This goes through the usual setup of a new machine, one step at a time."
    offer_step() {
        printf "\n${menu}%s${normal}\n" "$2"
        describe "$1"
        echo
        if ask_yes "Do this step?" "$3"; then
            run_task "$2" "$4"
        else
            RESULTS+=("skipped $2")
        fi
    }
    offer_step 2 "Update the system" "yes" update_system
    offer_step 3 "Common tools" "yes" install_other_programs
    offer_step 4 "WAGO login script" "yes" install_wago_login
    offer_step 5 "Automatic security updates" "yes" install_unattended_upgrades
    offer_step 7 "Cockpit" "yes" install_cockpit
    offer_step 9 "Fail2ban" "yes" install_fail2ban
    offer_step 12 "Docker" "no" install_docker
    offer_step 6 "Firewall" "yes" install_ufw
    offer_step 8 "Tailscale" "no" install_tailscale
}

# Display menu and handle user choice
check_user
load_nvm
clear
while true; do
    show_menu
    case $opt in
        1) recommended_setup ;;
        i|I) show_all_descriptions; clear; continue ;;
        2) offer_task 2 "Update the system" update_system ;;
        3) offer_task 3 "Common tools" install_other_programs ;;
        4) offer_task 4 "WAGO login script" install_wago_login ;;
        5) offer_task 5 "Automatic security updates" install_unattended_upgrades ;;
        6) offer_task 6 "Firewall" install_ufw ;;
        7) offer_task 7 "Cockpit" install_cockpit ;;
        8) offer_task 8 "Tailscale" install_tailscale ;;
        9) offer_task 9 "Fail2ban" install_fail2ban ;;
        10) offer_task 10 "File server (Samba)" install_file_server ;;
        11) offer_task 11 "Join a Windows domain" join_domain ;;
        12) offer_task 12 "Docker and Docker Compose" install_docker ;;
        13) offer_task 13 "LazyDocker" install_lazydocker ;;
        14) offer_task 14 "Portainer" install_portainer ;;
        15) offer_task 15 "Node-RED" install_nodered ;;
        16) offer_task 16 "Node.js" install_nodejs ;;
        17) offer_task 17 "Java" install_java ;;
        18) offer_task 18 "OPC UA Commander" install_opcua_commander ;;
        19) offer_task 19 "opcilloscope" install_opcilloscope ;;
        20) offer_task 20 "Mosquitto" install_mosquitto ;;
        21) offer_task 21 "EKBPRO KNX Terminal" install_knx_terminal ;;
        22) offer_task 22 "InfluxDB" install_influxdb ;;
        23) offer_task 23 "Grafana" install_grafana ;;
        24) offer_task 24 "Ignition" install_ignition ;;
        25) offer_task 25 "Bitwarden CLI" install_bitwarden_cli ;;
        x|X) printf "Exiting...\n"; exit 0 ;;
        *) clear; continue ;;
    esac
    show_results
    printf "\nPress enter to go back to the menu: "
    read -r
    clear
done
