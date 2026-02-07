#!/bin/bash
python3 -m venv wago_energymeter_slave_env
source wago_energymeter_slave_env/bin/activate
pip install pymodbus
echo "Environment ready. Run with: python wago_energymeter_slave.py"
