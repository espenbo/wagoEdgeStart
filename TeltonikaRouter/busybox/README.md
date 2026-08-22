# Teltonika SMS on BusyBox (WAGO PFC)

Shell scripts to send SMS via a Teltonika RUTX router from a WAGO PFC (BusyBox Linux). Each version lives in its own folder with its own README:

| Folder | Script | Description |
|---|---|---|
| [`sendsms_busybox/`](sendsms_busybox/README.md) | `sendsms_busybox.sh` | Minimal, works out of the box on BusyBox `/bin/sh`. Settings are edited directly in the script. |
| [`sendsms_busyboxV2/`](sendsms_busyboxV2/README.md) | `sendsms_busyboxV2.sh` | Hardened: config/env support, CLI args, retries with backoff, syslog, TLS options. |
| [`sendsms_busyboxV3/`](sendsms_busyboxV3/README.md) | `sendsms_busyboxV3.sh` | Recommended. Rewritten from V2: stricter error handling, distinct exit codes per failure stage, safer temp-file/credential handling, and no REST/CGI fallback (REST API only). |

## Requirements

- BusyBox `/bin/sh` (ash)
- Tools: `curl`, `awk`, `grep`, `mktemp`, `date`, `printf`, `chmod`, `rm`, `sleep`
  - `sendsms_busybox.sh` and `sendsms_busyboxV2.sh` additionally require `xxd` and `tr` (used to URL-encode the CGI fallback request)
- Optional: `logger` for syslog integration (BusyBox usually has it)

> **Note:** These scripts do **not** use `jq` or `sed`, and avoid bash-isms.

## Install

Copy the script folder to your PLC (e.g., `/root/`) and make the script executable:

```sh
chmod 700 /root/sendsms_busyboxV3/sendsms_busyboxV3.sh
```

## Which version should I use?

Use **V3** for anything new — see [`sendsms_busyboxV3/README.md`](sendsms_busyboxV3/README.md) for full usage, configuration, and exit codes.

V1 and V2 are kept for reference and existing deployments; see their own READMEs for details.
