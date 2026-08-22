#!/bin/sh
#
# sendsms_busyboxV3.sh
#
# Send SMS through Teltonika RUTX Web API from BusyBox / WAGO PFC.
#
# Tested design target:
#   - BusyBox ash / POSIX sh
#   - Teltonika RUTX09 / RutOS 7.x
#
# Usage:
#   ./sendsms_busyboxV3.sh "+4791919191" "Alarm from WAGO"
#
# Config:
#   /etc/teltonika-sms.conf
#
# Exit codes:
#   0   SMS accepted by Teltonika API
#   2   Invalid arguments/config
#   10  Login failed
#   11  No API token
#   20  Failed to read modem status
#   21  No modem ID
#   30  SMS API request failed
#   31  SMS API returned failure
#   127 Missing required command
#

set -u

PATH="/sbin:/bin:/usr/sbin:/usr/bin"
export PATH

# ============================================================
# Defaults
# ============================================================

ROUTER_IP="${ROUTER_IP:-192.168.1.1}"
USERNAME="${USERNAME:-admin}"
PASSWORD="${PASSWORD:-}"

CONF_FILE="${CONF_FILE:-/etc/teltonika-sms.conf}"

# Optional fixed modem ID.
# Leave empty to discover modem using /api/modems/status.
MODEM_ID="${MODEM_ID:-}"

# TLS
# INSECURE=1:
#   Accept Teltonika self-signed certificate.
#
# Better:
#   INSECURE=0
#   CACERT=/path/to/ca.pem
INSECURE="${INSECURE:-1}"
CACERT="${CACERT:-}"

CONNECT_TIMEOUT="${CONNECT_TIMEOUT:-5}"
MAX_TIME="${MAX_TIME:-20}"

# Retry login/status operations.
RETRIES="${RETRIES:-3}"
BACKOFF_BASE="${BACKOFF_BASE:-2}"

# IMPORTANT:
# SMS transmission is NOT automatically retried.
# Retrying an uncertain POST can result in duplicate SMS.
SMS_RETRIES="${SMS_RETRIES:-1}"

SYSLOG_TAG="${SYSLOG_TAG:-sendsms}"
QUIET="${QUIET:-0}"

# ============================================================
# Load configuration
# ============================================================

if [ -f "$CONF_FILE" ]; then
    # shellcheck disable=SC1090
    . "$CONF_FILE"
fi

# ============================================================
# Logging
# ============================================================

# Timestamped log line, printed to stdout (unless QUIET=1) and mirrored to
# syslog via logger (if available). Used for both progress and error output.
log()
{
    _msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"

    if [ "${QUIET:-0}" != "1" ]; then
        printf '%s\n' "$_msg"
    fi

    if command -v logger >/dev/null 2>&1; then
        logger -t "$SYSLOG_TAG" -- "$_msg" 2>/dev/null || true
    fi
}

# Log an error message and exit with the given code.
#
# Usage:
#   die <exit_code> <message...>
die()
{
    _code="$1"
    shift
    log "ERROR: $*"
    exit "$_code"
}

# Abort with exit code 127 if the given command is not available on PATH.
# Called once per required tool during startup so missing dependencies are
# reported up front instead of failing mid-script with a cryptic error.
need_cmd()
{
    command -v "$1" >/dev/null 2>&1 ||
        die 127 "Required command not found: $1"
}

# ============================================================
# Requirements
# ============================================================

need_cmd curl
need_cmd awk
need_cmd grep
need_cmd mktemp
need_cmd date
need_cmd printf
need_cmd cat
need_cmd rm
need_cmd chmod
need_cmd sleep

# ============================================================
# Temporary files
# ============================================================

# Space-separated list of temp files created via new_tmp(), removed by
# cleanup() on exit. Credentials and API responses pass through these files,
# so they are tracked here to guarantee removal even on error/signal exit.
TMP_FILES=""

# Create a new temp file (mode 600), register it for cleanup, and print its
# path on stdout. Callers capture the path with command substitution, e.g.:
#   _response_file="$(new_tmp)"
new_tmp()
{
    _f="$(mktemp /tmp/teltonika_sms.XXXXXX)" ||
        die 2 "Unable to create temporary file"

    chmod 600 "$_f" 2>/dev/null || true
    TMP_FILES="$TMP_FILES $_f"
    printf '%s\n' "$_f"
}

# Remove every temp file registered via new_tmp(). Installed as a trap below
# so login/API responses never survive on disk after the script exits.
cleanup()
{
    for _f in $TMP_FILES; do
        rm -f "$_f" 2>/dev/null || true
    done
}

trap cleanup EXIT HUP INT TERM

# ============================================================
# JSON helpers
# ============================================================

# Escape a shell string sufficiently for JSON string values.
# Handles:
#   \
#   "
#   tab
#   CR
#   newline
json_escape()
{
    printf '%s' "$1" |
    awk '
        BEGIN {
            ORS = ""
            quote = sprintf("%c", 34)
            slash = sprintf("%c", 92)
            tab = sprintf("%c", 9)
            cr = sprintf("%c", 13)
        }

        {
            if (NR > 1)
                printf "%c%c", 92, 110

            for (i = 1; i <= length($0); i++) {
                c = substr($0, i, 1)

                if (c == slash) {
                    printf "%c%c", 92, 92
                }
                else if (c == quote) {
                    printf "%c%c", 92, 34
                }
                else if (c == tab) {
                    printf "%c%c", 92, 116
                }
                else if (c == cr) {
                    printf "%c%c", 92, 114
                }
                else {
                    printf "%s", c
                }
            }
        }
    '
}

# Extract first JSON string value matching a key.
#
# Example:
#   printf "%s" "$JSON" | json_get_string token
#
# Intended for simple Teltonika API responses without jq.
json_get_string()
{
    _key="$1"

    awk -v key="$_key" '
        BEGIN {
            quote = sprintf("%c", 34)
        }

        {
            data = data $0
        }

        END {
            search = quote key quote

            p = index(data, search)
            if (p == 0)
                exit

            data = substr(data, p + length(search))

            p = index(data, ":")
            if (p == 0)
                exit

            data = substr(data, p + 1)

            # Remove whitespace before opening quote
            sub(/^[ \t\r\n]*/, "", data)

            if (substr(data, 1, 1) != quote)
                exit

            data = substr(data, 2)

            p = index(data, quote)
            if (p == 0)
                exit

            print substr(data, 1, p - 1)
        }
    '
}

# True (exit 0) if stdin contains "success": true anywhere in the JSON body.
json_success_true()
{
    grep -q '"success"[[:space:]]*:[[:space:]]*true'
}

# ============================================================
# CURL
# ============================================================

# Run a single curl request, writing the response body to $_outfile and
# printing the HTTP status code on stdout. TLS verification mode is chosen
# from the CACERT/INSECURE globals (see "Defaults" section above):
#   1. CACERT set and readable -> verify against that CA bundle
#   2. INSECURE=1              -> skip verification (curl -k)
#   3. otherwise               -> default curl verification
#
# Usage:
#   HTTP_CODE="$(curl_once "$outfile" <curl args...>)"
curl_once()
{
    _outfile="$1"
    shift

    if [ -n "${CACERT:-}" ] && [ -r "$CACERT" ]; then

        curl \
            -sS \
            --connect-timeout "$CONNECT_TIMEOUT" \
            --max-time "$MAX_TIME" \
            --cacert "$CACERT" \
            -o "$_outfile" \
            -w '%{http_code}' \
            "$@"

    elif [ "${INSECURE:-0}" = "1" ]; then

        curl \
            -sS \
            -k \
            --connect-timeout "$CONNECT_TIMEOUT" \
            --max-time "$MAX_TIME" \
            -o "$_outfile" \
            -w '%{http_code}' \
            "$@"

    else

        curl \
            -sS \
            --connect-timeout "$CONNECT_TIMEOUT" \
            --max-time "$MAX_TIME" \
            -o "$_outfile" \
            -w '%{http_code}' \
            "$@"
    fi
}


# Performs HTTP request with retry.
#
# Global outputs:
#
#   HTTP_CODE
#   HTTP_BODY
#   CURL_RC
#
http_request()
{
    _attempts="$1"
    shift

    _attempt=1
    _delay="$BACKOFF_BASE"

    HTTP_CODE="000"
    HTTP_BODY=""
    CURL_RC=0

    while :; do

        _response_file="$(new_tmp)"

        set +e
        HTTP_CODE="$(curl_once "$_response_file" "$@")"
        CURL_RC=$?
        set -e

        HTTP_BODY="$(cat "$_response_file" 2>/dev/null || true)"

        rm -f "$_response_file" 2>/dev/null || true

        # curl/network failure
        if [ "$CURL_RC" -ne 0 ]; then
            _retry="1"

        else
            case "$HTTP_CODE" in
                2??)
                    return 0
                    ;;

                # Retry transient server/rate-limit failures.
                429|500|502|503|504)
                    _retry="1"
                    ;;

                *)
                    # Do not retry ordinary 4xx API errors.
                    return 0
                    ;;
            esac
        fi

        if [ "$_attempt" -ge "$_attempts" ]; then
            return 0
        fi

        log "HTTP attempt $_attempt failed (HTTP=$HTTP_CODE curl=$CURL_RC). Retry in ${_delay}s"

        sleep "$_delay"

        _delay=$((_delay * 2))
        _attempt=$((_attempt + 1))
    done
}

# ============================================================
# CLI
# ============================================================

show_help()
{
    cat <<EOF
Usage:
  $0 <NUMBER> <MESSAGE>

Example:
  $0 "+4791919191" "Alarm from WAGO"

Configuration file:
  $CONF_FILE

Supported variables:

  ROUTER_IP
  USERNAME
  PASSWORD
  MODEM_ID

  INSECURE=0|1
  CACERT=/path/to/ca.pem

  CONNECT_TIMEOUT=5
  MAX_TIME=20

  RETRIES=3
  BACKOFF_BASE=2

  # Default 1 to avoid accidental duplicate SMS
  SMS_RETRIES=1

  SYSLOG_TAG=sendsms
  QUIET=0|1

Exit codes:
  0    SMS accepted
  2    Invalid configuration/arguments
  10   Login failed
  11   No token
  20   Modem API failed
  21   Modem ID missing
  30   SMS HTTP request failed
  31   SMS API reported failure
  127  Required command missing
EOF
}

case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
esac

NUMBER="${1:-}"
MESSAGE="${2:-}"

[ -n "$ROUTER_IP" ] ||
    die 2 "ROUTER_IP is not configured"

[ -n "$USERNAME" ] ||
    die 2 "USERNAME is not configured"

[ -n "$PASSWORD" ] ||
    die 2 "PASSWORD is not configured"

[ -n "$NUMBER" ] ||
    die 2 "Missing destination number"

[ -n "$MESSAGE" ] ||
    die 2 "Missing SMS message"

BASE_URL="https://$ROUTER_IP"

# ============================================================
# JSON escaped values
# ============================================================

JSON_USER="$(json_escape "$USERNAME")"
JSON_PASS="$(json_escape "$PASSWORD")"
JSON_NUMBER="$(json_escape "$NUMBER")"
JSON_MESSAGE="$(json_escape "$MESSAGE")"

# ============================================================
# 1. Login
# ============================================================

log "1/3 Login to Teltonika API"

LOGIN_JSON="$(new_tmp)"

printf \
    '{"username":"%s","password":"%s"}' \
    "$JSON_USER" \
    "$JSON_PASS" \
    > "$LOGIN_JSON"

http_request "$RETRIES" \
    -X POST \
    "$BASE_URL/api/login" \
    -H 'Content-Type: application/json' \
    --data-binary "@$LOGIN_JSON"

if [ "$CURL_RC" -ne 0 ]; then
    die 10 "Unable to reach Teltonika API (curl=$CURL_RC)"
fi

case "$HTTP_CODE" in
    2??)
        ;;
    *)
        die 10 "Login failed: HTTP $HTTP_CODE: $HTTP_BODY"
        ;;
esac

TOKEN="$(
    printf '%s' "$HTTP_BODY" |
        json_get_string token
)"

[ -n "$TOKEN" ] ||
    die 11 "Login succeeded but API token was not found"

log "Login successful"

# ============================================================
# 2. Find modem
# ============================================================

if [ -n "${MODEM_ID:-}" ]; then

    log "2/3 Using configured modem ID: $MODEM_ID"

else

    log "2/3 Reading modem status"

    http_request "$RETRIES" \
        -X GET \
        "$BASE_URL/api/modems/status" \
        -H "Authorization: Bearer $TOKEN"

    if [ "$CURL_RC" -ne 0 ]; then
        die 20 "Unable to read modem status (curl=$CURL_RC)"
    fi

    case "$HTTP_CODE" in
        2??)
            ;;
        *)
            die 20 "Modem API failed: HTTP $HTTP_CODE: $HTTP_BODY"
            ;;
    esac

    MODEM_ID="$(
        printf '%s' "$HTTP_BODY" |
            json_get_string id |
            awk 'NR == 1 { print; exit }'
    )"

    [ -n "$MODEM_ID" ] ||
        die 21 "No modem ID found in /api/modems/status"

    log "Detected modem ID: $MODEM_ID"
fi

# ============================================================
# 3. Send SMS
# ============================================================

log "3/3 Sending SMS to $NUMBER"

JSON_MODEM="$(json_escape "$MODEM_ID")"

SMS_JSON="$(new_tmp)"

printf \
    '{"data":{"number":"%s","message":"%s","modem":"%s"}}' \
    "$JSON_NUMBER" \
    "$JSON_MESSAGE" \
    "$JSON_MODEM" \
    > "$SMS_JSON"

#
# WARNING:
#
# SMS_RETRIES defaults to 1.
#
# If a network timeout occurs after the router has accepted the
# SMS but before the HTTP response reaches the PLC, automatically
# repeating the POST could send the SMS twice.
#
http_request "$SMS_RETRIES" \
    -X POST \
    "$BASE_URL/api/messages/actions/send" \
    -H 'Content-Type: application/json' \
    -H "Authorization: Bearer $TOKEN" \
    --data-binary "@$SMS_JSON"

if [ "$CURL_RC" -ne 0 ]; then
    die 30 "SMS request transport error (curl=$CURL_RC)"
fi

case "$HTTP_CODE" in
    2??)
        ;;
    *)
        die 30 "SMS request failed: HTTP $HTTP_CODE: $HTTP_BODY"
        ;;
esac

if printf '%s' "$HTTP_BODY" | json_success_true; then

    log "SUCCESS: SMS accepted by Teltonika API"
    exit 0

fi

die 31 "Teltonika API did not confirm SMS success: $HTTP_BODY"
