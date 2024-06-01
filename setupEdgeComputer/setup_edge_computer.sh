#!/bin/bash

# Oppdater pakkelisten og oppgrader systemet
echo "Oppdaterer systemet..."
apt update
apt upgrade -y

# Installer Tailscale
echo "Installerer Tailscale..."
curl -fsSL https://tailscale.com/install.sh | sh
tailscale up

# Installer Docker og Docker Compose
echo "Installerer Docker og Docker Compose..."
apt-get remove -y docker docker-engine docker.io containerd runc
apt-get update
apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Installer Cockpit
echo "Installerer Cockpit..."
apt-get install -y cockpit cockpit-bridge cockpit-networkmanager cockpit-packagekit cockpit-pcp cockpit-storaged cockpit-system cockpit-ws
systemctl enable --now cockpit.socket

# Installer nødvendige pakker for domenetilkobling
echo "Installerer nødvendige pakker for domenetilkobling..."
apt-get install -y realmd sssd sssd-tools libnss-sss libpam-sss adcli samba-common-bin oddjob oddjob-mkhomedir packagekit

# Oppdag og bli med i domenet
echo "Oppdager og blir med i domenet..."
realm discover yourdomain.com
realm join yourdomain.com

# Installer andre nødvendige programmer
echo "Installerer andre nødvendige programmer..."
apt-get install -y appstream bmon curl dnsutils exfat-fuse exfat-utils gnupg gpg-agent gpgconf iptables lm-sensors mc net-tools nfs-common ntfs-3g rsync rsyslog vim 

# Konfigurer Docker til å starte ved oppstart
echo "Konfigurerer Docker til å starte ved oppstart..."
systemctl enable docker

# Åpne Cockpit-porten i brannmuren
echo "Åpner Cockpit-porten i brannmuren..."
ufw allow 9090/tcp

# Konfigurer Samba hvis nødvendig for Windows-integrasjon
echo "Konfigurerer Samba..."
sed -i '/\[global\]/a workgroup = YOURDOMAIN\nsecurity = ads\nrealm = YOURDOMAIN.COM' /etc/samba/smb.conf

# Start Samba-tjenester
echo "Starter Samba-tjenester..."
systemctl restart smbd nmbd
systemctl enable smbd nmbd

# Last ned WAGO_LOGIN filen fra GitHub og legg den under /etc/
echo "Laster ned WAGO_LOGIN-filen fra GitHub..."
curl -o /etc/WAGO_LOGIN https://raw.githubusercontent.com/espenbo/wagoEdgeStart/main/WAGO_LOGIN

# Endre eier og rettigheter på filen
echo "Endrer eier og rettigheter på WAGO_LOGIN-filen..."
chown root:root /etc/WAGO_LOGIN
chmod 755 /etc/WAGO_LOGIN

# Sjekk om WAGO_LOGIN allerede er lagt til i /etc/profile
echo "Sjekker om WAGO_LOGIN allerede er lagt til i /etc/profile..."
if ! grep -q "/etc/WAGO_LOGIN" /etc/profile; then
  echo "Legger til WAGO_LOGIN i /etc/profile..."
  sed -i '/export TMOUT/a /etc/WAGO_LOGIN' /etc/profile
else
  echo "WAGO_LOGIN er allerede lagt til i /etc/profile."
fi

# Start tjenester og test
echo "Starter og tester tjenester..."
systemctl start docker
systemctl start cockpit

echo "Oppsett fullført!"

