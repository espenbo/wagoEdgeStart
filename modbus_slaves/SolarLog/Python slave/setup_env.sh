#!/bin/bash
python3 -m venv solarlogg_env
source solarlogg_env/bin/activate
pip install pymodbus
echo "Environment ready. Run with: python solarlogg_slave.py"
