# WAGO Edge Setup

Scripts that install programs on a WAGO Edge Computer running Debian. You choose from a menu, and nothing is installed without you selecting it.

## Before you start

Run the scripts as a normal user with sudo rights, not as root and not with `sudo`. They ask for the sudo password themselves.

If you only have the root user, log in as root and create a user first (change `NAME`):

```sh
apt install -y sudo curl
adduser NAME
usermod -aG sudo NAME
```

Log in as the new user before you go on.

## setup_edge_computer.sh

Start it directly from GitHub:

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/espenbo/wagoEdgeStart/main/setupEdgeComputer/setup_edge_computer.sh)
```

Or from a copy of this repository:

```sh
./setup_edge_computer.sh
```

On a new machine, choose **1) Recommended setup**. It explains each step and asks before doing it, and shows what went well at the end. All other options can be run at any time. When you pick a number, the script explains what the program does and why you would use it, and asks before it installs anything. Choose `i` to read about all programs at once. A program that is already installed is marked `[installed]` in the menu.

| Option | Program | What it does |
|---|---|---|
| 1 | Recommended setup | Goes through the steps marked below, in a safe order |
| 2 | Update the system | Recommended. `apt update` and `apt upgrade` |
| 3 | Common tools | Recommended. htop, tmux, ncdu, mc, vim, rsync, curl, dnsutils, net-tools, bmon, iperf3, mbpoll (Modbus test), lm-sensors and more |
| 4 | WAGO login script | Recommended. Information about the machine when you log in |
| 5 | Automatic security updates | Recommended. unattended-upgrades |
| 6 | Firewall (UFW) | Recommended. You choose which ports to open |
| 7 | Cockpit | Recommended. Manage the machine in a browser on port 9090 |
| 8 | Tailscale | Offered, default no. Secure remote access, needs an account |
| 9 | Fail2ban | Recommended. Blocks an address for 10 minutes after 5 failed SSH logins |
| 10 | File server (Samba) | Share a folder with other machines |
| 11 | Join a Windows domain (realm) | Log in to this machine with domain users |
| 12 | Docker and Docker Compose | Offered, default no. Also installed when a program needs it |
| 13 | LazyDocker | Docker in the terminal, start it with `lzd` |
| 14 | Portainer | Docker in the browser on port 9443 |
| 15 | Node-RED | Official installer, also installs Node.js. Port 1880 |
| 16 | Node.js | JavaScript runtime, needed by some of the other programs |
| 17 | Java | Default JRE and JDK |
| 18 | OPC UA Commander | OPC UA client in the terminal |
| 19 | opcilloscope | OPC UA client in the terminal |
| 20 | Mosquitto | MQTT broker, answers on this machine only until you configure it |
| 21 | EKBPRO KNX Terminal | KNX SCADA in the terminal, see below |
| 22 | InfluxDB | Database for measurements. Port 8086, or 8181 for InfluxDB 3 |
| 23 | Grafana | Dashboards on port 3000. First login is `admin` / `admin` |
| 24 | Ignition | SCADA platform from Inductive Automation on port 8088 |
| 25 | Bitwarden CLI | Bitwarden client in the terminal, see below |

### Installation methods

Some programs can be installed in more than one way. The script asks, and the first choice is the recommended one.

| Program | Methods |
|---|---|
| Node.js | NodeSource (version 24 unless you choose another), Debian, NVM |
| OPC UA Commander | NPM, Snap, Docker |
| LazyDocker | Download the program, Docker (amd64 only) |
| InfluxDB | InfluxDB 2 as a service, InfluxDB 2 in Docker, InfluxDB 3 Core in Docker |
| Grafana | Service, Docker |
| Ignition | Docker, installer from Inductive Automation |
| Bitwarden CLI | Download the program, NPM (needs Node.js 22 or newer), Snap (amd64 only) |

### Bitwarden CLI

The official Bitwarden client for the terminal, started with `bw`. It connects to your Bitwarden account and does not run a server, so no port is opened. Run option 25 again to update the downloaded version.

```sh
bw config server https://your-server    # only if you run your own Bitwarden server
bw login
export BW_SESSION="$(bw unlock --raw)"
bw get password NAME
bw lock
```

The session key unlocks the vault, so keep it in the terminal and out of files and scripts.

### File server or domain?

These are two different things, and you can use one, the other or both.

- **File server (option 10)** shares a folder, so other machines can open it. This is what you want on a small network. You choose a name, a folder, and whether a password is needed. In Windows you then open `\\IP-address\share`.
- **Join a domain (option 11)** connects this machine to an existing Windows domain, so domain users can log in to the machine with SSH. This suits a larger network with Active Directory. It does not share any files on its own.

With both, shared folders still use the Samba users made on this machine, not domain users. Other machines log in with the user and password you chose in option 10.

### Good to know

- **Firewall and SSH:** SSH is opened before anything is closed. The script finds the port in the SSH settings, among listening programs and from your own connection, with 22 as a fallback. Existing rules are kept unless you choose to delete them.
- **Firewall and programs:** the firewall step asks about each port, and the default answer is yes for programs that are installed. A program installed while the firewall is running opens its own port. Mosquitto and the OPC UA test servers are the exceptions, they stay closed unless you say otherwise.
- **Docker and the firewall:** ports published by Docker containers go past UFW, so they are open whatever the firewall says. This applies to Portainer, and to Grafana, InfluxDB and Ignition in Docker. The firewall step lists them.
- **Ignition:** commercial software. Without a license it runs as a trial that stops every 2 hours until you reset it. You accept the license yourself, on the first page in the browser or in the installer. The download server does not accept scripts, so with the installer method you download the file in a browser and copy it to the machine.
- **InfluxDB and Grafana:** measurements fill up the disk over time. Set a retention period on your buckets.
- **Cockpit:** the network page needs NetworkManager. The script leaves the network alone unless you ask, and will not touch a machine with a fixed IP address, because that could cut your connection.

## install_knx_terminal.sh

Installs [EKBPRO KNX Terminal Python](https://github.com/espenbo/ekbpro-knx-terminal-python). It is started from option 21, or on its own with `./install_knx_terminal.sh`.

The script:

1. installs the program
2. asks for the KNX project from ETS (upload from your PC, a path on the machine or a URL)
3. asks how the machine is connected to KNX
4. sets up the floor plan
5. starts the server as a systemd service

### Rooms in the project

If the project has ETS functions, the rooms come from ETS. Otherwise they are built from the group address structure, which in a project sorted by function gives "rooms" such as `Switch` and `Dimming value`. Then the floor plan cannot be linked to real rooms.

If the group address names hold a room code, for example `Switch - H1012 - Airlock`, add this to `project:` in `config.yaml`. Change the pattern to your room codes, and list your main groups under `floors`:

```yaml
project:
  rooms:
    pattern: "(H\\d{4})"
    floors: {0: "1st floor", 1: "1st floor", 2: "1st floor"}
```

Without `floors`, the same room is listed once per main group, and the floor plan only reaches one of them. Run `./scada import` and restart the service afterwards. See the program's [configuration guide](https://github.com/espenbo/ekbpro-knx-terminal-python/blob/main/docs/04-configuration.md#rooms-from-the-group-address-names).

### Floor plan

`knx_plan_wizard.py` makes the floor plan, one floor at a time. It reads the rooms from a PNG or JPG drawing, or you type them row by row, for example `Kitchen 3,3, Bath 2, Hall 1,9`.

- A drawing needs clean lines, on a light or dark background, and it may be turned up to 20 degrees.
- You enter the outer width of the building in metres, because a drawing has no scale.
- The result is shown in the terminal, where rooms can be deleted, merged or added, and linked to rooms in ETS.
- Rooms are rectangles, so an L-shaped room becomes its bounding box.
- This works best on simple drawings with closed rooms. On a real CAD drawing with many open passages, rooms can be merged or split wrongly. Then it is often faster to type the rooms by hand.

## reset_setupedge.sh

Removes what the setup script installed, one program at a time or everything. Run it the same way, as a normal user:

```sh
./reset_setupedge.sh
```

You confirm each removal by typing `yes`. Choosing "Remove everything" asks about each program in turn.

- `sudo`, `curl`, `gnupg` and `rsyslog` are never removed.
- Containers and images in `/var/lib/docker` are only deleted if you confirm that separately.
- Node-RED flows in `~/.node-red` are kept, and so are the folders shared by the file server.
- Removing the Bitwarden CLI deletes its login and local copy of the vault. Your Bitwarden account is not touched.
- Removing InfluxDB, Grafana or Ignition in Docker deletes their data, and you are told so first. Ignition from the installer is removed with the uninstaller in `/usr/local/bin/ignition`.
- Removing KNX Terminal deletes its folder, with the KNX project and all logged data.

Contributions are welcome. Please fork the repository and submit a pull request.

Use these scripts at your own risk, and make sure you have backups of important data before running them.
