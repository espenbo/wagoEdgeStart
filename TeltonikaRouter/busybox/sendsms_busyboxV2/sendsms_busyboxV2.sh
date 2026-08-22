#!/bin/sh
# BusyBox-ash compatible hardened version
# Adds: config/env support, CLI args, retries with backoff, syslog logging, TLS options
# Requires: sh, curl, awk, grep, xxd, tr, mktemp, date, printf, logger (optional but recommended)

set -eu

PATH="/sbin:/bin:/usr/sbin:/usr/bin"

# ===== Defaults (can be overridden by /etc/teltonika-sms.conf or env) =====
ROUTER_IP="${ROUTER_IP:-192.168.1.1}"
USERNAME="${USERNAME:-admin}"
PASSWORD="${PASSWORD:-passwd}"

# TLS options:
INSECURE="${INSECURE:-1}"                   # 1 = allow self-signed (curl -k); 0 = verify
CACERT="${CACERT:-}"                        # e.g., /etc/ssl/certs/teltonika-ca.pem (if set, used instead of -k)
CONNECT_TIMEOUT="${CONNECT_TIMEOUT:-5}"
MAX_TIME="${MAX_TIME:-20}"

# Retry/backoff:
RETRIES="${RETRIES:-3}"                     # total attempts
BACKOFF_BASE="${BACKOFF_BASE:-2}"           # seconds; exponential backoff 2,4,8...

# Logging:
SYSLOG_TAG="${SYSLOG_TAG:-sendsms}"
QUIET="${QUIET:-0}"                         # 1 = no stdout, only syslog

CONF_FILE="${CONF_FILE:-/etc/teltonika-sms.conf}"
[ -f "$CONF_FILE" ] && . "$CONF_FILE"

log() {
  msg="[$(date +'%H:%M:%S')] $*"
  [ "$QUIET" -eq 0 ] && echo "$msg"
  command -v logger >/dev/null 2>&1 && logger -t "$SYSLOG_TAG" -- "$msg" || true
}

need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing '$1'"; exit 127; }; }
need_cmd curl
need_cmd awk
need_cmd grep
need_cmd xxd
need_cmd tr
need_cmd mktemp
need_cmd date
need_cmd printf

# --- JSON helpers ---
json_get_string() { # $1=key
  awk -v key="$1" '
    BEGIN{ RS=""; FS="\"" key "\":\"" }
    NF>1 { split($2, a, "\""); print a[1]; exit }
  '
}
json_has_success_true() { grep -q '"success"[[:space:]]*:[[:space:]]*true' >/dev/null 2>&1; }

# --- URL-encode using xxd ---
rawurlencode() {
  hex="$(printf '%s' "$1" | xxd -p | tr -d '\n')"
  out=""; i=1; len=${#hex}
  while [ $i -le $len ]; do out="${out}%${hex:$i-1:2}"; i=$((i+2)); done
  printf '%s' "$out"
}

# ===== TLS/CURL builder =====
build_curl_base() {
  CURL_OPTS="-sS --connect-timeout $CONNECT_TIMEOUT --max-time $MAX_TIME"
  if [ -n "$CACERT" ] && [ -r "$CACERT" ]; then
    CURL_OPTS="$CURL_OPTS --cacert $CACERT"
  elif [ "${INSECURE:-0}" = "1" ]; then
    CURL_OPTS="$CURL_OPTS -k"
  fi
  printf '%s' "$CURL_OPTS"
}

# ===== Retry wrapper for curl; returns BODY and sets CODE_VAR =====
curl_retry_split() {
  # usage: curl_retry_split VAR_BODY VAR_CODE [curl args...]
  _var_body="$1"; _var_code="$2"; shift 2
  n=0
  while :; do
    _tmp="$(mktemp)"
    _code="$(curl $(build_curl_base) -o "$_tmp" -w '%{http_code}' "$@")" || _code="000"
    _body="$(cat "$_tmp")"
    rm -f "$_tmp"
    # HTTP 2xx success?
    case "$_code" in
      200|201|202|204) eval "$_var_code=\$_code"; eval "$_var_body=\$_body"; return 0 ;;
    esac
    n=$((n+1))
    if [ "$n" -ge "$RETRIES" ]; then
      eval "$_var_code=\$_code"; eval "$_var_body=\$_body"; return 0
    fi
    sleep_time=$(( BACKOFF_BASE ** n ))
    log "retry $_code in ${sleep_time}s ..."
    sleep "$sleep_time"
  done
}

# ===== CLI =====
# Usage: sendsms_busyboxV2.sh <NUMBER> <MESSAGE>
if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  cat <<EOF
Usage: $0 <NUMBER> <MESSAGE>
Env/config overrides:
  ROUTER_IP, USERNAME, PASSWORD
  INSECURE=0|1, CACERT=/path/to/ca.pem
  RETRIES, BACKOFF_BASE, CONNECT_TIMEOUT, MAX_TIME
  SYSLOG_TAG, QUIET=0|1, CONF_FILE=/etc/teltonika-sms.conf
EOF
  exit 0
fi

NUMBER="${1:-}"
MESSAGE="${2:-}"
[ -n "$ROUTER_IP" ] && [ -n "$USERNAME" ] && [ -n "$PASSWORD" ] || { echo "Missing ROUTER_IP/USERNAME/PASSWORD"; exit 2; }
[ -n "$NUMBER" ] && [ -n "$MESSAGE" ] || { echo "Usage: $0 <NUMBER> <MESSAGE>"; exit 2; }

ENC_MSG="$(rawurlencode "$MESSAGE")"
ENC_NUM="$(rawurlencode "$NUMBER")"
ENC_USER="$(rawurlencode "$USERNAME")"
ENC_PASS="$(rawurlencode "$PASSWORD")"

# ===== 1) Login → token =====
log "1/4 Fetching token from /api/login ..."
LOGIN_BODY=""; HTTP_CODE="000"
curl_retry_split LOGIN_BODY HTTP_CODE \
  -X POST "https://$ROUTER_IP/api/login" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\"}"

log "HTTP $HTTP_CODE Response: $LOGIN_BODY"
TOKEN="$(printf '%s' "$LOGIN_BODY" | json_get_string token)"
[ -n "${TOKEN:-}" ] || { log "❌ ERROR: Failed to retrieve token. Aborting."; exit 10; }
log "✅ Token obtained."

# ===== 2) Modem status → first modem id =====
log "2/4 Fetching modem ID ..."
MODEM_BODY=""; HTTP_CODE="000"
curl_retry_split MODEM_BODY HTTP_CODE \
  -X GET "https://$ROUTER_IP/api/modems/status" \
  -H "Authorization: Bearer $TOKEN"

log "HTTP $HTTP_CODE Response: (len=$(printf '%s' "$MODEM_BODY" | wc -c))"
MODEM_ID="$(printf '%s' "$MODEM_BODY" | json_get_string id | awk 'NR==1{print; exit}')"
[ -n "${MODEM_ID:-}" ] || { log "⚠️  No modem ID found, using '1-1'."; MODEM_ID="1-1"; }
log "✅ Modem ID: $MODEM_ID"

# ===== 3) REST send =====
log "3/4 Attempting REST API (/messages/actions/send) ..."
PAYLOAD="{\"data\":{\"number\":\"$NUMBER\",\"message\":\"$MESSAGE\",\"modem\":\"$MODEM_ID\"}}"
SMS_BODY=""; HTTP_CODE="000"
curl_retry_split SMS_BODY HTTP_CODE \
  -X POST "https://$ROUTER_IP/api/messages/actions/send" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d "$PAYLOAD"

log "HTTP $HTTP_CODE Response: $SMS_BODY"
if [ "$HTTP_CODE" -eq 200 ] && printf '%s' "$SMS_BODY" | json_has_success_true; then
  log "✅ SUCCESS: SMS sent via REST API."
  exit 0
elif printf '%s' "$SMS_BODY" | grep -qi 'not implemented'; then
  log "⚠️  Endpoint not implemented. Falling back to /cgi-bin/sms_send ..."
else
  log "⚠️  Unknown error. Trying fallback..."
fi

# ===== 4) Fallback CGI =====
log "4/4 Fallback: /cgi-bin/sms_send ..."
FALLBACK_BODY=""; HTTP_CODE="000"
curl_retry_split FALLBACK_BODY HTTP_CODE \
  -X POST "http://$ROUTER_IP/cgi-bin/sms_send" \
  -d "username=$ENC_USER" \
  -d "password=$ENC_PASS" \
  -d "number=$ENC_NUM" \
  -d "text=$ENC_MSG"

log "Fallback HTTP $HTTP_CODE response: $FALLBACK_BODY"
log "✅ Fallback completed."
exit 0
