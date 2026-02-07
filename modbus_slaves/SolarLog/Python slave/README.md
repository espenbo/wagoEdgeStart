# SolarLogg Modbus TCP Slave Simulator

This Python script simulates a **Solar-Log™ Modbus TCP PM (Power Management)** slave device, including functionality from the official Solar-Log™ Modbus TCP specification (version 2.17). It is useful for testing Modbus clients like SCADA systems, EMS controllers, or energy monitoring tools.

---

## 🌟 Features

- Fully functional **Modbus TCP slave**
- Simulates Power Control V2 and Live Data Compact (registers 3500+)
- Dynamic values for:
  - Active / Reactive power
  - Energy yields
  - Voltages, frequency, and more
- Complies with **Modbus TCP PM V2.17**
- Supports multiple Modbus slave units (default = 1)

---

## 🔧 Requirements

- Python 3.8+
- [`pymodbus`](https://github.com/pymodbus-dev/pymodbus) >= 3.0

Install dependencies:

```bash
pip install pymodbus
```

Or use the provided environment script:

```bash
bash setup_env.sh
```

---

## ▶️ How to Run

1. **Configure IP/Port in `solarlogg_slave.py`:**

```python
NUM_SLAVES = 1
IP_ADDRESS = "0.0.0.0"
PORT = 5020
```

2. **Start the simulator:**

```bash
python solarlogg_slave.py
```

---

## 📋 Example Registers

### PM - Power Control V2.17

| Register   | Name              | Type     | Example Value | Description                         |
|------------|-------------------|----------|----------------|-------------------------------------|
| 10200      | PLimit_Type       | uint16   | 2              | Active power limitation type        |
| 10201      | PLimitPerc        | uint16   | 80             | Power limitation in %               |
| 10204      | Reactive_Type     | uint16   | 4              | Reactive power control mode         |
| 10205-06   | CosPhi_Fix        | float32  | 0.97           | Fixed cos(phi)                      |
| 10209      | QPerc             | int16    | 125            | Reactive power in % of Pn           |
| 10211-12   | Watchdog_Tag      | uint32   | epoch          | Validity tag                        |
| 10218-19   | Utility_fUacRS    | float32  | 400.0          | Voltage phase R-S                   |
| 10224-25   | Utility_fPacR     | float32  | 2000.0         | Active power phase R                |
| 10230-31   | Utility_fPac_total| float32  | 5700.0         | Total active power output           |

### SolarLog Live Data (Registers 3500–3528) V unknown

| Register   | Name                      | Type     | Example Value | Description                                |
|------------|---------------------------|----------|----------------|--------------------------------------------|
| 3500-01    | lastUpdateTime            | uint32   | epoch          | Timestamp of last update                   |
| 3502-03    | Pac                       | uint32   | 4800           | Total inverter power output (W)            |
| 3508-09    | Daily yield               | uint32   | 123456         | Daily production (Wh)                      |
| 3516-17    | Total yield               | uint32   | 45,000,000     | Total production (Wh)                      |
| 3528-29    | Total yield consumption   | uint32   | 17,000,000     | Total consumption (Wh)                     |


---

## 🔁 Update Logic

- Register values update every 2 seconds
- Simulated dynamic data for power and energy
- Timestamp updates using `time.time()`

---

## 📚 Documentation

For full register reference, see:  
**`SolarLog_Datasheet_Modbus_TCP_PM_EN_V.2.17.pdf`**

---

## ⚠️ Disclaimer

This simulator is intended for **educational and testing purposes only**. It is not affiliated with or endorsed by Solar-Log™.  
For commercial use, consult Solar-Log™ licensing terms.

---

## 📦 Contents

- `solarlogg_slave.py` – Main simulator script
- `setup_env.sh` – Optional environment setup
- `SolarLog_Datasheet_Modbus_TCP_PM_EN_V.2.17.pdf` – Official register documentation
