# sendsms_busyboxV3.sh

Send an SMS through a Teltonika RUTX router's Web API from a WAGO PFC (BusyBox Linux).

This is the recommended version for new deployments. It builds on [`sendsms_busyboxV2.sh`](../sendsms_busyboxV2/README.md) with stricter error handling, distinct exit codes per failure stage, and safer temp-file/credential handling. Unlike V1 and V2, it does **not** fall back to the legacy `/cgi-bin/sms_send` endpoint — it talks to the modern REST API only, and fails loudly (with a specific exit code) if any step doesn't succeed.

## What it does

1. **Login** — `POST /api/login` with username/password, obtains a bearer token.
2. **Find modem** — uses `MODEM_ID` if configured, otherwise reads `GET /api/modems/status` and takes the first modem ID found.
3. **Send SMS** — `POST /api/messages/actions/send` with the token, number, message and modem ID.

Each stage is logged with a timestamp (to stdout, and to syslog if `logger` is available).

## Requirements

- BusyBox `/bin/sh` (ash) or any POSIX `sh`
- Tools: `curl`, `awk`, `grep`, `mktemp`, `date`, `printf`, `cat`, `rm`, `chmod`, `sleep`

The script checks for all of these on startup and exits with code `127` naming the first one missing, so there's no need to verify manually before running it.

## Usage

```sh
./sendsms_busyboxV3.sh "+4791919191" "Alarm from WAGO"
```

```sh
./sendsms_busyboxV3.sh --help
```

## Configuration

Settings are read in this order, each overriding the previous:

1. Built-in defaults (in the script)
2. `/etc/teltonika-sms.conf` (or the path in `$CONF_FILE`), if it exists
3. Environment variables set before invoking the script

A template config file is provided at [`teltonika-sms.conf`](teltonika-sms.conf) in this folder. Copy it into place and lock down its permissions, since it contains the router password in plain text:

```sh
cp teltonika-sms.conf /etc/teltonika-sms.conf
chmod 600 /etc/teltonika-sms.conf
```

### Supported variables

| Variable | Default | Description |
|---|---|---|
| `ROUTER_IP` | `192.168.1.1` | Router hostname or IP address (used as `https://$ROUTER_IP`). |
| `USERNAME` | `admin` | Router web UI / API username. |
| `PASSWORD` | *(empty — must be set)* | Router web UI / API password. |
| `MODEM_ID` | *(empty)* | Fixed modem ID to use. Leave empty to auto-detect via `/api/modems/status`. |
| `INSECURE` | `1` | `1` = accept the router's self-signed TLS certificate (`curl -k`). Set `0` and provide `CACERT` for proper verification. |
| `CACERT` | *(empty)* | Path to a CA bundle to verify the router's certificate against. Takes precedence over `INSECURE` when set and readable. |
| `CONNECT_TIMEOUT` | `5` | Seconds to wait for the TCP/TLS connection to establish. |
| `MAX_TIME` | `20` | Seconds allowed for the whole HTTP request. |
| `RETRIES` | `3` | Attempts for login and modem-status requests, with exponential backoff (`BACKOFF_BASE`, `2*BACKOFF_BASE`, ...). |
| `BACKOFF_BASE` | `2` | Base delay in seconds between retries. |
| `SMS_RETRIES` | `1` | Attempts for the SMS-send request specifically. See warning below. |
| `SYSLOG_TAG` | `sendsms` | Tag used when logging via `logger`. |
| `QUIET` | `0` | Set to `1` to suppress stdout output; syslog logging (if available) is unaffected. |
| `CONF_FILE` | `/etc/teltonika-sms.conf` | Path to the config file to source, if it exists. |

> **Why `SMS_RETRIES` defaults to `1`, unlike login/status:**
> If a network timeout happens *after* the router has accepted and sent the SMS but *before* the HTTP response reaches the PLC, blindly retrying that POST could send the SMS a second time. Login and modem-status lookups are read-only/idempotent and safe to retry automatically; the SMS-send step is not, so it isn't retried unless you deliberately raise `SMS_RETRIES`.

## Exit codes

The script uses a distinct exit code per failure stage, so calling code (e.g. a PLC alarm handler) can react differently to different failures:

| Code | Meaning |
|---|---|
| `0` | SMS accepted by the Teltonika API. |
| `2` | Invalid arguments or missing configuration (`ROUTER_IP`/`USERNAME`/`PASSWORD`/number/message). |
| `10` | Login request failed (network error or non-2xx response). |
| `11` | Login succeeded but no API token was found in the response. |
| `20` | Modem status request failed (network error or non-2xx response). |
| `21` | Modem status request succeeded but no modem ID was found. |
| `30` | SMS request failed (network error or non-2xx response). |
| `31` | SMS request returned 2xx but the API did not report `"success": true`. |
| `127` | A required command (see Requirements) is missing from `PATH`. |

## Security notes

- Temporary files (login payload, HTTP response bodies) are created with `mktemp`, `chmod 600`'d immediately, and removed on exit — including on `HUP`/`INT`/`TERM` — via a trap, so credentials and tokens don't linger on disk.
- The config file contains the router password in plain text; keep it `chmod 600` and owned by root.
- `INSECURE=1` (the default) disables TLS certificate verification, matching the RUTX's default self-signed certificate. For a stricter setup, install the router's CA certificate on the PLC and set `INSECURE=0` with `CACERT=/path/to/ca.pem`.

## Differences from V2

- No legacy CGI fallback — REST API only, so failures surface clearly instead of being silently retried against a different endpoint.
- Distinct exit codes per failure stage (see table above), instead of a generic failure/always-exit-0 pattern.
- SMS-send retries are decoupled from login/status retries (`SMS_RETRIES` vs `RETRIES`) to avoid duplicate messages.
- Temp files are tracked and cleaned up via an `EXIT`/`HUP`/`INT`/`TERM` trap.
- `--help` / `-h` prints usage, configuration variables, and exit codes.
