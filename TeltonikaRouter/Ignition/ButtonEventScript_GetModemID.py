def runAction(self, event):
	provider = self.view.params.Provider
	system = self.view.params.System
	router_ip = self.view.params.tailscalehost
	baseTagPath = "[{}]{}".format(provider, system)
	
	# Get modem ID
	try:
		import teltonikaApi.main as sms
		token = sms.getToken(router_ip, baseTagPath)
	
		if token:
			modem_id = sms.getModemID(router_ip, token)
			self.getSibling("lblModemID").props.text = "✅ Modem ID: {}".format(modem_id)
		else:
			self.getSibling("lblModemID").props.text = "❌ No token - can't get modem ID."
	
	except Exception as e:
		self.getSibling("lblModemID").props.text = "❌ Error: {}".format(str(e))