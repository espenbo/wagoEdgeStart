# Modbus slaves

Simulated Modbus TCP devices, for testing a PLC or SCADA system without the real hardware. Both answer on port 5020, so run one at a time or change `PORT` at the top of the script.

| Folder | Simulates |
|---|---|
| [SolarLog](SolarLog/Python%20slave/README.md) | Solar-Log Modbus TCP PM |
| `wago meter` | WAGO energy meter, 19 slaves (unit 1 to 19), with data sheets and a register list in `wago_modbus_registers.csv` |

Start the WAGO meter from `wago meter/Python slave`:

```sh
bash setup_env.sh
wago_energymeter_slave_env/bin/python wago_energymeter_slave.py
```

Both need pymodbus 3.10 to 3.12, which `setup_env.sh` installs. Version 3.13 and newer do not work with these scripts.
