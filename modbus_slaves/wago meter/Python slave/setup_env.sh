#!/bin/bash
python3 -m venv wago_energymeter_slave_env
source wago_energymeter_slave_env/bin/activate
pip install 'pymodbus>=3.10,<3.13'
echo "Environment ready. Run with: wago_energymeter_slave_env/bin/python wago_energymeter_slave.py"
