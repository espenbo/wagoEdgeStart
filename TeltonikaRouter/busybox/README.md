# Teltonika SMS on BusyBox (WAGO PFC)

Two shell scripts to send SMS via a Teltonika RUTX router from a WAGO PFC (BusyBox Linux).

- `sendsms_busybox.sh` — minimal, works out of the box on BusyBox `/bin/sh`.
- `sendsms_busyboxV2.sh` — hardened: config/env support, CLI args, retries, syslog, TLS options.

## Requirements

- BusyBox `/bin/sh` (ash)
- Tools: `curl`, `awk`, `grep`, `xxd`, `tr`, `mktemp`, `date`, `printf`
- Optional: `logger` for syslog integration (BusyBox usually has it)

> **Note:** These scripts do **not** use `jq` or `sed`, and avoid bash-isms.

## Install

Copy the scripts to your PLC (e.g., `/root/`) and make them executable:

```sh
chmod 700 /root/sendsms_busybox.sh
chmod 700 /root/sendsms_busyboxV2.sh

## basic sendsms_busybox.sh
Edit the header variables inside sendsms_busybox.sh (ROUTER_IP, USERNAME, PASSWORD, NUMBER, MESSAGE), then:
```sh
./sendsms_busybox.sh

## Hardened V2 (recommended) sendsms_busyboxV2.sh
Provide number and message as arguments:
```sh
./sendsms_busyboxV2.sh "+4791916159" "Hello from WAGO"

You can override settings via env vars or a config file.

### Configuration (V2)

Create /etc/teltonika-sms.conf (root-only):
```sh
ROUTER_IP=100.65.37.82
USERNAME=admin
PASSWORD='change-me'
# TLS:
# INSECURE=0
# CACERT=/etc/ssl/certs/teltonika-ca.pem
# Retries/timeouts:
# RETRIES=3
# BACKOFF_BASE=2
# CONNECT_TIMEOUT=5
# MAX_TIME=20
# Logging:
# SYSLOG_TAG=sendsms
# QUIET=0

Permissions:
```sh
chmod 600 /etc/teltonika-sms.conf