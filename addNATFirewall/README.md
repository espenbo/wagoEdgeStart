# NAT and firewall

`nattfirewall.sh` lets machines on a local network reach the internet through this machine. It turns on IP forwarding, sets up NAT and configures UFW.

Set the variables at the top of the script first:

| Variable | Default | Meaning |
|---|---|---|
| `INTERNET_IFACE` | `eth0` | Port facing the internet |
| `LAN_IFACE` | `eth1` | Port facing the local network |
| `LAN_SUBNET` | `192.168.1.0/24` | Addresses on the local network |

```sh
sudo ./nattfirewall.sh
```

The script opens SSH on the standard port only, so change it first if SSH uses another port. All traffic from the local network to this machine is allowed. New connections from the internet to the local network are stopped.

Run it once. Running it again adds the NAT rules a second time.
