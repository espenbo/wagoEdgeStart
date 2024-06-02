#!/bin/bash

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

# Function to display all tasks in a table format
display_tasks() {
    echo -e "\n+----------------------------------------------------------------------------------------------------------------------------------------------------+"
    echo -e "| All tasks to perform on a new install                                                                                                               |"
    echo -e "+----------------------------------------------------------------------------------------------------------------------------------------------------+"
    echo -e "| 1 | Run 'apt update' and 'apt upgrade -y'                                                                                                            |"
    echo -e "+----------------------------------------------------------------------------------------------------------------------------------------------------+"
    echo -e "| 2 | Install Tailscale                                                                                                                               |"
    echo -e "+----------------------------------------------------------------------------------------------------------------------------------------------------+"
    echo -e "| 3 | Install UFW firewall manager. Lock down all. Open ports ssh:22, web:80,443, modbus:502                                                          |"
    echo -e "|   |  OPC/UA Discovery Server:4840,4843 Reference Server: 62540,62541 Data Access Server:62546,62547 Generic Client:61210,61211                      |"    
    echo -e "+----------------------------------------------------------------------------------------------------------------------------------------------------+"
    echo -e "| 4 | Install Cockpit web manager                                                                                                                     |"
    echo -e "+----------------------------------------------------------------------------------------------------------------------------------------------------+"
    echo -e "| 5 | Install Docker and Docker Compose from https://download.docker.com/linux/debian                                                                 |"
    echo -e "+----------------------------------------------------------------------------------------------------------------------------------------------------+"
    echo -e "| 6 | Install Samba and domain functionality                                                                                                          |"
    echo -e "+----------------------------------------------------------------------------------------------------------------------------------------------------+"
    echo -e "| 7 | Install other necessary programs                                                                                                                |"
    echo -e "+----------------------------------------------------------------------------------------------------------------------------------------------------+"
    echo -e "| 8 | Install WAGO login script                                                                                                                       |"
    echo -e "+----------------------------------------------------------------------------------------------------------------------------------------------------+"
    echo -e "| 9 | Setup Samba and domain                                                                                                                          |"
    echo -e "+----------------------------------------------------------------------------------------------------------------------------------------------------+"
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

# Install other necessary programs
install_other_programs() {
  echo "Installing other programs..."
  apt-get install -y appstream bmon curl dnsutils exfat-fuse exfat-utils gnupg gpg-agent gpgconf iptables lm-sensors mc net-tools nfs-common ntfs-3g rsync rsyslog vim
}

# Install WAGO login script
install_wago_login() {
  echo "Downloading WAGO_LOGIN file from GitHub..."
  curl -o /etc/WAGO_LOGIN https://raw.githubusercontent.com/espenbo/wagoEdgeStart/main/WAGO_LOGIN
  echo "Changing owner and permissions of WAGO_LOGIN file..."
  chown root:root /etc/WAGO_LOGIN
  chmod 755 /etc/WAGO_LOGIN
  echo "Checking if WAGO_LOGIN is already added to /etc/profile..."
  if ! grep -q "/etc/WAGO_LOGIN" /etc/profile; then
    echo "Adding WAGO_LOGIN to /etc/profile..."
    sed -i '/export TMOUT/a /etc/WAGO_LOGIN' /etc/profile
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

# Display all tasks
display_tasks

# Menu for user to choose a task
echo "Enter the number corresponding to the task you want to perform:"
read -r choice

case $choice in
    1) update_system ;;
    2) install_tailscale ;;
    3) install_ufw ;;
    4) install_cockpit ;;
    5) install_docker ;;
    6) install_samba_domain ;;
    7) install_other_programs ;;
    8) install_wago_login ;;
    9) setup_samba_domain ;;
    *) echo "Invalid choice" ;;
esac

echo "Setup complete!"
