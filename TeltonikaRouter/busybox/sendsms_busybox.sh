#!/bin/sh
# BusyBox-ash compatible (no bashisms, no jq, no sed, no GNU od)
# Requires: sh, curl, awk, grep, xxd, tr, mktemp, date, printf

set -eu

# ==============================
# Configuration
ROUTER_IP="192.168.1.1"
USERNAME="admin"
PASSWORD="passwd"
NUMBER="+4791919191"
MESSAGE="Debug test SMS"
# ==============================

log() { printf '[%s] %s\n' "$(date +'%H:%M:%S')" "$*"; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing '$1'"; exit 127; }; }

need_cmd curl
need_cmd awk
need_cmd grep
need_cmd xxd
need_cmd tr
need_cmd mktemp
need_cmd date
need_cmd printf

# --- JSON helpers (BusyBox-friendly) ---
# Extract first string after "key":"..."; naive but fine for token/id/etc.
json_get_string() { # $1=key
  awk -v key="$1" '
    BEGIN{ RS=""; FS="\"" key "\":\"" }
    NF>1 {
      split($2, a, "\""); print a[1]; exit
    }
  '
}

json_has_success_true() {
  grep -q '"success"[[:space:]]*:[[:space:]]*true' >/dev/null 2>&1
}

# --- URL-encode using xxd (no GNU od) ---
rawurlencode() { # $1=string
  # percent-encode every byte: safe for CGI and special chars
  # xxd -p gives hex without spaces; we print %HH per byte.
  hex="$(printf '%s' "$1" | xxd -p | tr -d '\n')"
  out=""
  i=1
  len=${#hex}
  while [ $i -le $len ]; do
    out="${out}%${hex:$i-1:2}"
    i=$((i+2))
  done
  printf '%s' "$out"
}

ENC_MSG="$(rawurlencode "$MESSAGE")"
ENC_NUM="$(rawurlencode "$NUMBER")"
ENC_USER="$(rawurlencode "$USERNAME")"
ENC_PASS="$(rawurlencode "$PASSWORD")"

# Curl wrapper: split body/code without head/tail/sed
curl_split() {
  # usage: curl_split VAR_BODY VAR_CODE [curl args...]
  _var_body="$1"; _var_code="$2"; shift 2
  _tmp="$(mktemp)"
  _code="$(curl -sk -o "$_tmp" -w '%{http_code}' "$@")"
  eval "$_var_code=\$_code"
  _body="$(cat "$_tmp")"
  rm -f "$_tmp"
  eval "$_var_body=\$_body"
}

# ========== 1. Fetch Token ==========
log "1/4 Fetching token from /api/login ..."
LOGIN_BODY=""; HTTP_CODE=""
curl_split LOGIN_BODY HTTP_CODE \
  -X POST "https://$ROUTER_IP/api/login" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\"}"

log "HTTP $HTTP_CODE Response: $LOGIN_BODY"

TOKEN="$(printf '%s' "$LOGIN_BODY" | json_get_string token)"

if [ -z "${TOKEN:-}" ]; then
  log "❌ ERROR: Failed to retrieve token. Aborting."
  exit 1
fi
log "✅ Token obtained: $TOKEN"

# ========== 2. Get Modem ID ==========
log "2/4 Fetching modem ID ..."
MODEM_BODY=""; HTTP_CODE=""
curl_split MODEM_BODY HTTP_CODE \
  -X GET "https://$ROUTER_IP/api/modems/status" \
  -H "Authorization: Bearer $TOKEN"

log "HTTP $HTTP_CODE Response: $MODEM_BODY"

# Take first "id":"..." found
MODEM_ID="$(printf '%s' "$MODEM_BODY" | json_get_string id | awk 'NR==1{print; exit}')"

if [ -z "${MODEM_ID:-}" ]; then
  log "⚠  WARNING: No modem ID found. Using default '1-1'."
  MODEM_ID="1-1"
else
  log "✅ Modem ID: $MODEM_ID"
fi

# ========== 3. Try REST API SMS ==========
log "3/4 Attempting REST API (/messages/actions/send) ..."
PAYLOAD="{\"data\":{\"number\":\"$NUMBER\",\"message\":\"$MESSAGE\",\"modem\":\"$MODEM_ID\"}}"

SMS_BODY=""; HTTP_CODE=""
curl_split SMS_BODY HTTP_CODE \
  -X POST "https://$ROUTER_IP/api/messages/actions/send" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d "$PAYLOAD"

log "HTTP $HTTP_CODE Response: $SMS_BODY"

if [ "$HTTP_CODE" -eq 200 ] && printf '%s' "$SMS_BODY" | json_has_success_true; then
  log "✅ SUCCESS: SMS sent via REST API."
  exit 0
elif printf '%s' "$SMS_BODY" | grep -qi 'not implemented'; then
  log "⚠  Endpoint not implemented. Falling back to /cgi-bin/sms_send ..."
else
  log "⚠  Unknown error. Trying fallback..."
fi

# ========== 4. Fallback ==========
log "4/4 Fallback: Sending SMS via /cgi-bin/sms_send ..."
FALLBACK_BODY=""; HTTP_CODE=""
curl_split FALLBACK_BODY HTTP_CODE \
  -X POST "http://$ROUTER_IP/cgi-bin/sms_send" \
  -d "username=$ENC_USER" \
  -d "password=$ENC_PASS" \
  -d "number=$ENC_NUM" \
  -d "text=$ENC_MSG"

log "Fallback HTTP $HTTP_CODE response: $FALLBACK_BODY"
log "✅ Fallback completed. Script done."