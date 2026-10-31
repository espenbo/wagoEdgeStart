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
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-nat.conf
sysctl --system

# Konfigurer iptables for NAT
iptables -t nat -A POSTROUTING -s $LAN_SUBNET -o $INTERNET_IFACE -j MASQUERADE
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

# Tillat videresending fra LAN til internett. Svar slipper inn av seg selv, ny trafikk fra internett stoppes.
ufw route allow in on $LAN_IFACE out on $INTERNET_IFACE

# Aktiver UFW
ufw enable

echo "NAT og UFW konfigurasjon fullført."
