#!/bin/bash
set -euo pipefail

# ==============================
# Konfigurasjon
ROUTER_IP="192.168.1.1"
USERNAME="admin"
PASSWORD="passwd"
NUMBER="+4791919191"
MESSAGE="Debug test SMS"
# ==============================

log() { echo "[$(date +'%H:%M:%S')] $*"; }

# ========== 1. Fetch Token ==========
log "1/4 Fetching token from /api/login ..."
TOKEN_RESPONSE=$(curl -sk -X POST "https://$ROUTER_IP/api/login" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\"}" \
  -w "\n%{http_code}")

HTTP_CODE=$(echo "$TOKEN_RESPONSE" | tail -n1)
TOKEN_BODY=$(echo "$TOKEN_RESPONSE" | head -n -1)

log "HTTP $HTTP_CODE Response: $TOKEN_BODY"
TOKEN=$(echo "$TOKEN_BODY" | jq -r '.data.token // empty')

if [ -z "$TOKEN" ]; then
  log "❌ ERROR: Failed to retrieve token. Aborting."
  exit 1
fi
log "✅ Token obtained: $TOKEN"

# ========== 2. Get Modem ID ==========
log "2/4 Fetching modem ID ..."
MODEM_RESPONSE=$(curl -sk -X GET "https://$ROUTER_IP/api/modems/status" \
  -H "Authorization: Bearer $TOKEN" \
  -w "\n%{http_code}")

HTTP_CODE=$(echo "$MODEM_RESPONSE" | tail -n1)
MODEM_BODY=$(echo "$MODEM_RESPONSE" | head -n -1)

log "HTTP $HTTP_CODE Response: $MODEM_BODY"
MODEM_ID=$(echo "$MODEM_BODY" | jq -r '.data[0].id // "1-1"')

if [ -z "$MODEM_ID" ]; then
  log "⚠️  WARNING: No modem ID found. Using default '1-1'."
  MODEM_ID="1-1"
else
  log "✅ Modem ID: $MODEM_ID"
fi

# ========== 3. Try REST API SMS ==========
log "3/4 Attempting REST API (/messages/actions/send) ..."
PAYLOAD="{\"data\":{\"number\":\"$NUMBER\",\"message\":\"$MESSAGE\",\"modem\":\"$MODEM_ID\"}}"

SMS_RESPONSE=$(curl -sk -X POST "https://$ROUTER_IP/api/messages/actions/send" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d "$PAYLOAD" -w "\n%{http_code}")

HTTP_CODE=$(echo "$SMS_RESPONSE" | tail -n1)
SMS_BODY=$(echo "$SMS_RESPONSE" | head -n -1)

log "HTTP $HTTP_CODE Response: $SMS_BODY"

if [ "$HTTP_CODE" -eq 200 ] && echo "$SMS_BODY" | grep -q '"success":true'; then
  log "✅ SUCCESS: SMS sent via REST API."
  exit 0
elif echo "$SMS_BODY" | grep -q 'not implemented'; then
  log "⚠️  Endpoint not implemented. Falling back to /cgi-bin/sms_send ..."
else
  log "⚠️  Unknown error. Trying fallback..."
fi

# ========== 4. Fallback ==========
log "4/4 Fallback: Sending SMS via /cgi-bin/sms_send ..."
FALLBACK_RESPONSE=$(curl -sk -X POST "http://$ROUTER_IP/cgi-bin/sms_send" \
  -d "username=$USERNAME" \
  -d "password=$PASSWORD" \
  -d "number=$NUMBER" \
  -d "text=$MESSAGE")

log "Fallback response: $FALLBACK_RESPONSE"
log "✅ Fallback completed. Script done."
