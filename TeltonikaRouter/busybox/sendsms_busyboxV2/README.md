# sendsms_busyboxV2.sh

Hardened version of [`sendsms_busybox.sh`](../sendsms_busybox/README.md) for sending SMS through a Teltonika RUTX router's Web API from a WAGO PFC (BusyBox Linux).

> This is kept for existing deployments and reference. For new deployments, use [`sendsms_busyboxV3/`](../sendsms_busyboxV3/README.md), which refines the error handling and safety around this version.

## What's new compared to V1

- Command-line arguments instead of hardcoded number/message.
- Configuration via `/etc/teltonika-sms.conf` or environment variables.
- Retry with exponential backoff on failed HTTP requests.
- Optional syslog logging via `logger`.
- TLS options: accept self-signed certs (`INSECURE=1`, default) or verify against a CA bundle (`CACERT=...`).

## What it does

1. Logs in to `/api/login` to obtain a bearer token (retried on failure).
2. Reads `/api/modems/status` to find a modem ID (retried on failure; falls back to `1-1` if none is found).
3. Sends the SMS via `POST /api/messages/actions/send` (retried on failure).
4. If that REST call does not report success, falls back to the legacy `GET/POST /cgi-bin/sms_send` endpoint.

## Requirements

- BusyBox `/bin/sh` (ash)
- Tools: `curl`, `awk`, `grep`, `xxd`, `tr`, `mktemp`, `date`, `printf`
- Optional: `logger` for syslog integration

## Usage

```sh
./sendsms_busyboxV2.sh "+4791919191" "Hello from WAGO"
```

Settings can be overridden via environment variables or a config file.

## Configuration

Create `/etc/teltonika-sms.conf` (root-only):

```sh
ROUTER_IP=192.168.1.1
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
```

```sh
chmod 600 /etc/teltonika-sms.conf
```

## Known limitations

- The SMS-send request is retried like any other request, which risks sending a duplicate SMS if the router accepts the message but the response is lost in transit. [`sendsms_busyboxV3/`](../sendsms_busyboxV3/README.md) fixes this by giving the SMS-send step its own (non-retried by default) attempt count.
- If the REST send does not confirm success, the script silently falls back to the legacy CGI endpoint and always exits `0` at the end — the caller cannot reliably tell from the exit code whether the SMS actually went out.
- No distinct exit code for "modem status lookup failed" or "SMS request failed" — only login failure (`10`), missing arguments/config (`2`), and missing commands (`127`) are distinguished.
- Temp files created for curl response bodies are not guaranteed to be cleaned up on error/signal exit.
