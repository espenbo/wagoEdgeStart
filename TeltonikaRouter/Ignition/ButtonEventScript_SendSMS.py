def runAction(self, event):
    # Get user input
	number = self.getSibling("txtNumber").props.text
	message = self.getSibling("txtMessage").props.text
	label = self.getSibling("lblResult")
	
	# Get view parameters
	provider = self.view.params.Provider
	system = self.view.params.System
	#router_ip = self.view.params.tailscalehost
	router_ip = self.view.params.lanip
	
	# Construct base tag path
	baseTagPath = "[{}]{}".format(provider, system)
	
	# Input validation
	if not number or not message:
		label.props.text = "❌ Please enter both number and message."
	elif not router_ip:
		label.props.text = "❌ Missing router IP (tailscalehost param)."
	else:
		try:
			# Import and call SMS script
			import teltonikaApi.main as sms
	
			sms.sendSMS(
				router_ip = router_ip,
				baseTagPath = baseTagPath,
				recipient = number,
				message = message
			)
	
			label.props.text = "✅ SMS sent to {}".format(number)
	
		except Exception as e:
			label.props.text = "❌ Error: {}".format(str(e))