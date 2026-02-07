#!/usr/bin/env bash
set -euo pipefail

# get_topology_status.sh — Teltonika RUTX Topology (devices_scan + status per docs schema)
# Req: curl, jq
# Examples:
#   ./get_topology_status3.sh --router 192.168.1.1 --user admin --pass 'secret'
#   ./get_topology_status3.sh --router 192.168.1.1 --user admin --pass 'secret' --scan --iface lan
#   ./get_topology_status3.sh -r 192.168.1.1 -u admin -p secret --scan --iface both --json

ROUTER_IP="192.168.1.1"
USERNAME="admin"
PASSWORD="passwd"
DO_SCAN=false
IFACE="both"
TIMEOUT=45
OUTPUT_JSON=false


log() { echo "[$(date +'%H:%M:%S')] $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

while (( "$#" )); do
  case "$1" in
    -r|--router) ROUTER_IP="${2:?}"; shift 2;;
    -u|--user)   USERNAME="${2:?}"; shift 2;;
    -p|--pass)   PASSWORD="${2:?}"; shift 2;;
    --scan)      DO_SCAN=true; shift;;
    --iface)     IFACE="${2:?}"; shift 2;;
    --timeout)   TIMEOUT="${2:?}"; shift 2;;
    --json)      OUTPUT_JSON=true; shift;;
    -h|--help)
      cat <<'EOF'
Usage:
  get_topology_status3.sh --router <ip> --user <u> --pass <p> [--scan] [--iface lan|wan|both] [--json]

Notes:
  - --scan posts to /api/topology/actions/devices_scan with {"data":{"scan_type":"lan|wan|all"}}
  - /api/topology/status returns data.interfaces[]
EOF
      exit 0;;
    *) die "Unknown argument: $1";;
  esac
done

[[ -n "$ROUTER_IP" && -n "$USERNAME" && -n "$PASSWORD" ]] || \
  die "Missing required args. Use --router --user --pass."

# Map our --iface to scan_type expected by API
case "$IFACE" in
  lan)   SCAN_TYPE="lan" ;;
  wan)   SCAN_TYPE="wan" ;;
  both)  SCAN_TYPE="all" ;;   # docs use one value; "all" is the common pattern
  *)     die "--iface must be lan|wan|both" ;;
esac

# 1) Login
log "1/3 Logging in to https://$ROUTER_IP/api/login ..."
LOGIN=$(curl -sk -X POST "https://$ROUTER_IP/api/login" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\"}" -w "\n%{http_code}")
HTTP=$(echo "$LOGIN" | tail -n1); BODY=$(echo "$LOGIN" | head -n -1)
[[ "$HTTP" == "200" ]] || die "Login failed (HTTP $HTTP): $BODY"
TOKEN=$(echo "$BODY" | jq -r '.data.token // empty')
[[ -n "$TOKEN" ]] || die "No token in login response"
log "✅ Token acquired"

SCAN_DEVICES_JSON=''
if $DO_SCAN; then
  log "2/3 Running devices_scan (scan_type: $SCAN_TYPE) ..."
  SCAN_REQ="{\"data\":{\"scan_type\":\"$SCAN_TYPE\"}}"
  SCAN_RESP=$(curl -sk -X POST "https://$ROUTER_IP/api/topology/actions/devices_scan" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$SCAN_REQ" -w "\n%{http_code}")
  SHTTP=$(echo "$SCAN_RESP" | tail -n1)
  SBODY=$(echo "$SCAN_RESP" | head -n -1)

  [[ "$SHTTP" == "200" ]] || die "devices_scan failed (HTTP $SHTTP): $SBODY"
  [[ "$(echo "$SBODY" | jq -r '.success // false')" == "true" ]] || {
    echo "$SBODY" | jq . >&2 || true
    die "devices_scan did not return success:true"
  }

  # Extract devices array for later pretty print
  SCAN_DEVICES_JSON=$(echo "$SBODY" | jq -c '.data.devices // []')
  log "🧭 devices_scan returned $(echo "$SCAN_DEVICES_JSON" | jq 'length') device(s)"
fi

# 3) Get topology status (interfaces[])
log "3/3 Fetching topology status ..."
STATUS=$(curl -sk -X GET "https://$ROUTER_IP/api/topology/status" \
  -H "Authorization: Bearer $TOKEN" -w "\n%{http_code}")
THTTP=$(echo "$STATUS" | tail -n1)
TBODY=$(echo "$STATUS" | head -n -1)
[[ "$THTTP" == "200" ]] || die "GET /topology/status failed (HTTP $THTTP): $TBODY"

# Output JSON if requested (includes scan devices if any)
if $OUTPUT_JSON; then
  # Merge devices (if scanned) alongside interfaces for convenience
  if $DO_SCAN; then
    jq --argjson devs "$SCAN_DEVICES_JSON" '.devices=$devs' <<<"$TBODY"
  else
    echo "$TBODY" | jq .
  fi
  exit 0
fi

# Pretty print (1) scanned devices and (2) interfaces
if $DO_SCAN; then
  echo
  echo "=== Discovered Devices (from devices_scan) ==="
  echo "$SCAN_DEVICES_JSON" | jq -r '
    (["IP","MAC","IFACE","TYPE","HOSTNAME","VENDOR","NAME"]),
    (.[]? | [(.ip//"-"),(.mac//"-"),(.interface//"-"),(.type//"-"),(.hostname//"-"),(.vendor//"-"),(.name//"-")]) | @tsv' \
  | column -t -s $'\t'
fi

echo
echo "=== Interfaces (from /topology/status) ==="
echo "$TBODY" | jq -r '
  .data.interfaces // [] |
  (["IFACE","NAME","TYPE","PROTO","IP","DEVICE","DISABLED","STATUS"]),
  ( .[]? | [(.interface//"-"),(.name//"-"),(.type//"-"),(.proto//"-"),(.ip//"-"),(.device//"-"),(.disabled//"-"),(.status//"-")] ) | @tsv' \
| column -t -s $'\t'
