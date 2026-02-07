# Ignition Jython 2.7 script for sending SMS via Teltonika router API
# Includes fallback to /cgi-bin/sms_send if REST API fails
# Supports dynamic baseTagPath with provider (e.g. "[default]routers/site-a")

# Example Usage in Script Console:
# teltonikaApi.main.sendSMS(
#     router_ip = "192.168.1.1",
#     baseTagPath = "[RouterTeltonika]Router/rutx11",
#     recipient = "+4791919191",
#     message = "Test SMS from Ignition with fallback support"
# )

# Example Gateway Timer Script (every 5 minutes):
# if system.date.getMinute(system.date.now()) % 5 == 0:
# 	teltonikaApi.main.getToken(
# 		"192.168.1.1",
# 		"[RouterTeltonika]Router/rutx11"
# 	)

import system
import urllib2
import json
import ssl

def getCredentials(baseTagPath):
	"""
	Reads the username and password from memory tags under the given tag path.
	Example baseTagPath: "[RouterTeltonika]Router/rutx11"
	"""
	try:
		usernamePath = "{}/username".format(baseTagPath)
		passwordPath = "{}/password".format(baseTagPath)

		[userTag, passTag] = system.tag.readBlocking([usernamePath, passwordPath])
		username = userTag.value
		password = passTag.value

		return username, password
	except Exception as e:
		system.util.getLogger("Teltonika").error("Error reading credentials: {}".format(str(e)))
		return None, None


def getToken(router_ip, baseTagPath):
	"""
	Logs in to the Teltonika API and returns a bearer token.
	Also stores the full response to [baseTagPath]/TokenResponse
	"""
	logger = system.util.getLogger("Teltonika")

	username, password = getCredentials(baseTagPath)
	if not username or not password:
		logger.error("Missing credentials for: {}".format(baseTagPath))
		return None

	url = "https://{}/api/login".format(router_ip)
	data = json.dumps({
		"username": username,
		"password": password
	})

	try:
		req = urllib2.Request(url, data)
		req.add_header("Content-Type", "application/json")

		# Bypass SSL verification for self-signed certificates
		context = ssl._create_unverified_context()
		response = urllib2.urlopen(req, timeout=5, context=context)

		resp_text = response.read()
		tokenData = json.loads(resp_text)
		token = tokenData["data"]["token"]

		# Optional: write response to tag for debugging
		tokenTag = "{}/TokenResponse".format(baseTagPath)
		system.tag.writeBlocking([tokenTag], [resp_text])

		logger.info("✅ Token retrieved successfully for {}".format(baseTagPath))
		return token

	except Exception as e:
		logger.error("❌ Failed to get token for {}: {}".format(baseTagPath, str(e)))
		return None


def getModemID(router_ip, token):
	"""
	Queries the modem ID from /api/modems/status
	Returns first modem ID, or "1-1" as fallback
	"""
	logger = system.util.getLogger("Teltonika")
	url = "https://{}/api/modems/status".format(router_ip)

	try:
		req = urllib2.Request(url)
		req.add_header("Authorization", "Bearer {}".format(token))

		context = ssl._create_unverified_context()
		response = urllib2.urlopen(req, timeout=5, context=context)

		resp_text = response.read()
		data = json.loads(resp_text)

		if "data" in data and len(data["data"]) > 0:
			modem_id = data["data"][0].get("id", "1-1")
			logger.info("✅ Modem ID retrieved: {}".format(modem_id))
			return modem_id
		else:
			logger.warn("⚠️ No modem ID found, using default '1-1'")
			return "1-1"

	except Exception as e:
		logger.error("❌ Failed to retrieve modem ID: {}".format(str(e)))
		return "1-1"


def sendSMS(router_ip, baseTagPath, recipient, message):
	"""
	Main function for sending SMS via REST API (with fallback).
	Arguments:
		router_ip     = IP address of the router
		baseTagPath   = Memory tag base path with [provider] (e.g. "[RouterTeltonika]Router/rutx11")
		recipient     = Phone number in international format (e.g. "+4791919191")
		message       = Text message to send
	"""
	logger = system.util.getLogger("Teltonika")

	username, password = getCredentials(baseTagPath)
	if not username or not password:
		logger.error("🚫 Missing credentials.")
		return

	token = getToken(router_ip, baseTagPath)
	if token:
		modem_id = getModemID(router_ip, token)

		url = "https://{}/api/messages/actions/send".format(router_ip)

		payload = {
			"data": {
				"number": recipient,
				"message": message,
				"modem": modem_id
			}
		}

		data = json.dumps(payload)

		req = urllib2.Request(url, data)
		req.add_header("Content-Type", "application/json")
		req.add_header("Authorization", "Bearer {}".format(token))

		context = ssl._create_unverified_context()

		logger.info("📤 Attempting to send SMS via REST API to {} using modem {}".format(recipient, modem_id))

		try:
			response = urllib2.urlopen(req, timeout=5, context=context)
			resp_text = response.read()

			resp_data = json.loads(resp_text)
			if resp_data.get("success") == True:
				logger.info("✅ SMS sent successfully via REST API.")
			else:
				logger.warn("⚠️ REST API did not return success=true, trying fallback...")
				_fallbackSend(router_ip, username, password, recipient, message)

			# Optional: store response to tag
			resp_tag = "{}/LastSMSResponse".format(baseTagPath)
			system.tag.writeBlocking([resp_tag], [resp_text])

			return

		except Exception as e:
			logger.error("❌ REST API failed, falling back: {}".format(str(e)))

	# Fallback if token or API request fails
	_fallbackSend(router_ip, username, password, recipient, message)


def _fallbackSend(router_ip, username, password, recipient, message):
	"""
	Fallback method using the legacy /cgi-bin/sms_send HTTP endpoint.
	This does NOT use SSL and works without token.
	"""
	logger = system.util.getLogger("Teltonika")
	logger.warn("📡 Fallback: sending SMS via /cgi-bin/sms_send ...")

	try:
		url = "http://{}/cgi-bin/sms_send".format(router_ip)

		# Build POST body (form data)
		data = "username={}&password={}&number={}&text={}".format(
			username, password, recipient, message
		)

		req = urllib2.Request(url, data)
		req.add_header("Content-Type", "application/x-www-form-urlencoded")

		response = urllib2.urlopen(req, timeout=5)
		resp_text = response.read()

		logger.info("✅ SMS sent via fallback. Response: {}".format(resp_text))

	except Exception as e:
		logger.error("❌ Fallback SMS failed: {}".format(str(e)))

def getSerialStatus(router_ip, baseTagPath):
	"""
	Fetches serial port status from the Teltonika router.
	Returns parsed JSON response or None on failure.
	Also writes full response to a memory tag [baseTagPath]/SerialStatus
	"""
	logger = system.util.getLogger("Teltonika")

	token = getToken(router_ip, baseTagPath)
	if not token:
		logger.error("❌ Cannot fetch serial status: no token.")
		return None

	url = "https://{}/api/serial/status".format(router_ip)

	try:
		req = urllib2.Request(url)
		req.add_header("Authorization", "Bearer {}".format(token))

		context = ssl._create_unverified_context()
		response = urllib2.urlopen(req, timeout=5, context=context)

		resp_text = response.read()
		data = json.loads(resp_text)

		if data.get("success") == True:
			logger.info("✅ Serial status retrieved from {}".format(router_ip))

			# Optional: write to a memory tag
			tag_path = "{}/SerialStatus".format(baseTagPath)
			system.tag.writeBlocking([tag_path], [resp_text])

			return data["data"]
		else:
			logger.warn("⚠️ Serial status request failed: {}".format(resp_text))
			return None

	except Exception as e:
		logger.error("❌ Error retrieving serial status: {}".format(str(e)))
		return None

