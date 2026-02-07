from pymodbus.server import StartTcpServer
from pymodbus.datastore import ModbusServerContext, ModbusDeviceContext, ModbusSequentialDataBlock
from pymodbus.pdu.device import ModbusDeviceIdentification
import threading
import time
import struct

# -------------------------
# Configuration
# -------------------------
NUM_SLAVES = 1                   # Number of Modbus slave devices
#IP_ADDRESS = "192.168.1.189"    # IP address to bind server
IP_ADDRESS = "0.0.0.0"
PORT = 5020                     # Port number to listen on

# Helper: convert float to 2x16-bit registers
def float_to_regs(value):
    return list(struct.unpack(">HH", struct.pack(">f", value)))

# Helper: convert signed 32-bit int to 2x16-bit registers
def int32_to_regs(value):
    return list(struct.unpack(">HH", struct.pack(">i", value)))

# Initialize full holding register memory space
hr_data = [0] * 65536

# PM1 - Power Management (registers 10200+)
hr_data[10200] = 2  # PLimit_Type
hr_data[10201] = 80  # PLimitPerc
hr_data[10204] = 4  # Reactive_Type
hr_data[10205:10207] = float_to_regs(0.97)  # CosPhi_Fix
hr_data[10209] = 125  # QPerc
hr_data[10211:10213] = int32_to_regs(1)  # Watchdog_Tag
hr_data[10213:10215] = int32_to_regs(60)  # Watchdog_Time
hr_data[10215] = 60  # Watchdog_Limit
hr_data[10216] = 1  # Utility_connect_good
hr_data[10218:10220] = float_to_regs(400.0)  # Utility_fUacRS
hr_data[10220:10222] = float_to_regs(400.0)  # Utility_fUacST
hr_data[10222:10224] = float_to_regs(400.0)  # Utility_fUacTR
hr_data[10224:10226] = float_to_regs(2000.0)  # Utility_fPacR
hr_data[10226:10228] = float_to_regs(1900.0)  # Utility_fPacS
hr_data[10228:10230] = float_to_regs(1800.0)  # Utility_fPacT
hr_data[10230:10232] = float_to_regs(5700.0)  # Utility_fPac_total
hr_data[10232:10234] = float_to_regs(50.00)  # Utility_fFreq

# PM2 - Energy Counters (registers 10500+)
hr_data[10500:10502] = float_to_regs(12345.6)  # Utility_fYieldDay
hr_data[10502:10504] = float_to_regs(65432.1)  # Utility_fYieldTotal
hr_data[10504:10506] = float_to_regs(54321.0)  # Utility_fYieldYear
hr_data[10506:10508] = float_to_regs(43210.0)  # Utility_fYieldMonth
hr_data[10508:10510] = float_to_regs(3210.0)   # Utility_fYieldYesterday
hr_data[10510:10512] = float_to_regs(610.5)    # Utility_fPower
hr_data[10512:10514] = float_to_regs(610.5)    # Utility_fPower_inst
hr_data[10514] = 0  # Utility_Temp


# -------------------------
# SolarLogg Live Data (Registers 3500–3528)
# -------------------------
hr_data[3500:3502] = int32_to_regs(int(time.time()))    # 3500: lastUpdateTime (32bit unsigned, seconds)
hr_data[3502:3504] = int32_to_regs(4800)                # 3502: Pac (W) - Total Pac of all inverters
hr_data[3504:3506] = int32_to_regs(5000)                # 3504: Pac max (W) - Max Pac of all inverters
hr_data[3506] = 230                                     # 3506: Uac (V) - Average Uac of all inverters
hr_data[3507] = 550                                     # 3507: Iac (A) - Average Iac of all inverters
hr_data[3508:3510] = int32_to_regs(123456)              # 3508: Daily yield (Wh)
hr_data[3510:3512] = int32_to_regs(654321)              # 3510: Yesterday yield (Wh)
hr_data[3512:3514] = int32_to_regs(1500000)             # 3512: Monthly yield (Wh)
hr_data[3514:3516] = int32_to_regs(20000000)            # 3514: Yearly yield (Wh)
hr_data[3516:3518] = int32_to_regs(45000000)            # 3516: Total yield (Wh)
hr_data[3518:3520] = int32_to_regs(1200)                # 3518: Pac consumption (W) - Total Pac of all consumption meters
hr_data[3520:3522] = int32_to_regs(23456)               # 3520: Daily yield consumption (Wh)
hr_data[3522:3524] = int32_to_regs(19876)               # 3522: Yesterday yield consumption (Wh)
hr_data[3524:3526] = int32_to_regs(600000)              # 3524: Monthly yield consumption (Wh)
hr_data[3526:3528] = int32_to_regs(8000000)             # 3526: Yearly yield consumption (Wh)
hr_data[3528:3530] = int32_to_regs(17000000)            # 3528: Total yield consumption (Wh)


# -------------------------
# Modbus Server Setup
# Build device contexts
# -------------------------
device_contexts = {
    unit: ModbusDeviceContext(
        hr=ModbusSequentialDataBlock(0, hr_data.copy()), # holding registers
        ir=ModbusSequentialDataBlock(0, hr_data.copy())  # mirror holding -> input
    )
    for unit in range(1, NUM_SLAVES + 1)
}
context = ModbusServerContext(devices=device_contexts, single=False)

# Device identity
identity = ModbusDeviceIdentification()
identity.VendorName = "SolarLogSim"
identity.ProductCode = "SL1000"
identity.ProductName = "SolarLoggModbus"
identity.ModelName = "SL-Simulator"
identity.MajorMinorRevision = "1.0"

# -------------------------
# Simulation logic
# -------------------------
def update_registers():
    tick = 0
    while True:
        base = 2000 + (tick % 100)
# SolarLog_Datasheet_Modbus_TCP_PM_EN_V.2.17
        hr_data[10224:10226] = float_to_regs(base)
        hr_data[10226:10228] = float_to_regs(base - 50)
        hr_data[10228:10230] = float_to_regs(base - 100)
        hr_data[10230:10232] = float_to_regs(base * 3 - 150)
        hr_data[10500:10502] = float_to_regs(10000 + (tick % 500))
        hr_data[10510:10512] = float_to_regs(500 + (tick % 50))
        now = int(time.time())
        hr_data[10211:10213] = int32_to_regs(now)
# SolarLog_Unknown_version.png
        hr_data[3500:3502] = int32_to_regs(now)  # Update timestamp
        hr_data[3502:3504] = int32_to_regs(4800 + tick % 300)  # Sim Pac
        hr_data[3508:3510] = int32_to_regs(123456 + tick % 5000)
        hr_data[3516:3518] = int32_to_regs(45000000 + tick * 5)
        hr_data[3528:3530] = int32_to_regs(17000000 + tick * 4)

        # Update all slaves' holding and input registers
        for unit in range(1, NUM_SLAVES + 1):
            context[unit].setValues(3, 0, hr_data)  # Holding registers
            context[unit].setValues(4, 0, hr_data)  # Input registers

        tick += 1
        time.sleep(2)

# -------------------------
# Main program
# -------------------------
if __name__ == "__main__":
    threading.Thread(target=update_registers, daemon=True).start()
    print(f"Starting extended SolarLog Modbus slave on {IP_ADDRESS}:{PORT}…")
    StartTcpServer(context=context, identity=identity, address=(IP_ADDRESS, PORT))
