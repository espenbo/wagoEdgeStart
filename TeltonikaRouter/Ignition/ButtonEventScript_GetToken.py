def runAction(self, event):
	provider = self.view.params.Provider
	system = self.view.params.System
	router_ip = self.view.params.tailscalehost
	baseTagPath = "[{}]{}".format(provider, system)
	
	try:
		import teltonikaApi.main as sms
		token = sms.getToken(router_ip, baseTagPath)
	
		if token:
			self.getSibling("lblToken").props.text = "✅ Token: {}".format(token)
		else:
			self.getSibling("lblToken").props.text = "❌ Failed to get token."
	
	except Exception as e:
		self.getSibling("lblToken").props.text = "❌ Error: {}".format(str(e))