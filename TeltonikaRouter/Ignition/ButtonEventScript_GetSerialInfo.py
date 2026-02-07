def runAction(self, event):
	logger = system.util.getLogger("Teltonika")
	
	provider = self.view.params.Provider
	systemName = self.view.params.System
	router_ip = self.view.params.lanip
	baseTagPath = "[{}]{}".format(provider, systemName)
	
	token = None
	modem_id = None
	status_result = None
	
	try:
		import teltonikaApi.main as sms
		token = sms.getToken(router_ip, baseTagPath)
		modem_id = sms.getModemID(router_ip, token) if token else None
		status = sms.getSerialStatus(router_ip, baseTagPath)
		status_result = "OK" if status else "Failed"
	except Exception as e:
		logger.error("Error during serial info retrieval: {}".format(str(e)))
		status_result = "Error: {}".format(str(e))
	
	# Send to popup via session message
	system.perspective.sendMessage(
		messageType="updateSerialPopup",
		payload={
			"token": token,
			"modemID": modem_id,
			"status": status_result
		},
		scope="session"
	)