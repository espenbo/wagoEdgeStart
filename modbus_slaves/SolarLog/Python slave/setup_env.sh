#!/bin/bash
python3 -m venv solarlogg_env
source solarlogg_env/bin/activate
pip install 'pymodbus>=3.10,<3.13'
echo "Environment ready. Run with: solarlogg_env/bin/python solarlogg_slave.py"
