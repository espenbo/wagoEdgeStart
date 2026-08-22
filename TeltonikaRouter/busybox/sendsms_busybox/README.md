# sendsms_busybox.sh

Minimal script to send an SMS through a Teltonika RUTX router's Web API from a WAGO PFC (BusyBox Linux).

> This is the original, basic version. For a hardened version with CLI arguments, config file, retries and syslog support, see [`sendsms_busyboxV2/`](../sendsms_busyboxV2/README.md), or better yet [`sendsms_busyboxV3/`](../sendsms_busyboxV3/README.md).

## What it does

1. Logs in to `/api/login` to obtain a bearer token.
2. Reads `/api/modems/status` to find a modem ID (falls back to `1-1` if none is found).
3. Sends the SMS via `POST /api/messages/actions/send`.
4. If that REST call does not report success, falls back to the legacy `GET/POST /cgi-bin/sms_send` endpoint.

## Requirements

- BusyBox `/bin/sh` (ash)
- Tools: `curl`, `awk`, `grep`, `xxd`, `tr`, `mktemp`, `date`, `printf`

## Configuration

All settings are hardcoded at the top of the script — there is no config file or CLI arguments. Edit the header block before running:

```sh
ROUTER_IP="192.168.1.1"
USERNAME="admin"
PASSWORD="passwd"
NUMBER="+4791919191"
MESSAGE="Debug test SMS"
```

## Install & run

```sh
chmod 700 /root/sendsms_busybox.sh
./sendsms_busybox.sh
```

## Known limitations

- No CLI arguments — number/message must be edited into the script (or the script duplicated per destination).
- No retry/backoff on failed HTTP requests.
- TLS certificate verification is always skipped (`curl -k`).
- Credentials are stored in plain text inside the script itself.

These limitations are addressed in [`sendsms_busyboxV2/`](../sendsms_busyboxV2/README.md) and [`sendsms_busyboxV3/`](../sendsms_busyboxV3/README.md).
