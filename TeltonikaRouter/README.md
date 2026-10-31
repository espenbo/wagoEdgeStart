# Teltonika router

Send SMS and read status from Teltonika RUTX routers through the router's API. See `API link.txt` for the API reference.

| Folder | Runs on | Contents |
|---|---|---|
| `bash` | Linux with curl and jq | `send_sms.sh` for a test SMS, `get_topology_status.sh` to read the network topology |
| [busybox](busybox/README.md) | WAGO PFC | SMS script for BusyBox, use V3 |
| [codesys 3.5](codesys%203.5/README.md) | WAGO PFC300 | SMS alarm sender in CODESYS |
| `Ignition` | Ignition gateway | Script library `teltonikaApi.main.py` and button scripts for Perspective |

Scripts in this folder use example values. Do not commit real router passwords or phone numbers. A password given with `--pass` is visible to other users on the machine, so use it on test machines only.
