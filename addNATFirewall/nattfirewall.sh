#!/bin/bash

# Konfigurer variabler
INTERNET_IFACE="eth0"  # Grensesnittet koblet til internett
LAN_IFACE="eth1"       # Grensesnittet koblet til det lokale nettverket
LAN_SUBNET="192.168.1.0/24"  # Subnettet til det lokale nettverket

# Oppdater pakkelisten og installer nødvendige pakker
apt-get update
apt-get install -y ufw iptables-persistent

# Konfigurer NAT
echo "Konfigurerer NAT..."

# Aktiver IP videresending
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

# Konfigurer iptables for NAT
iptables -t nat -A POSTROUTING -o $INTERNET_IFACE -j MASQUERADE
iptables -A FORWARD -i $INTERNET_IFACE -o $LAN_IFACE -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i $LAN_IFACE -o $INTERNET_IFACE -j ACCEPT

# Lagre iptables-regler
netfilter-persistent save

# Konfigurer UFW
echo "Konfigurerer UFW..."

# Tillat SSH-tilkoblinger
ufw allow ssh

# Konfigurer UFW til å tillate trafikk fra LAN til internett
ufw allow in on $LAN_IFACE to any
ufw allow out on $LAN_IFACE to any

# Tillat videresending
ufw route allow in on $LAN_IFACE out on $INTERNET_IFACE
ufw route allow in on $INTERNET_IFACE out on $LAN_IFACE

# Aktiver UFW
ufw enable

echo "NAT og UFW konfigurasjon fullført."
