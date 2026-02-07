from pymodbus.server import StartTcpServer
from pymodbus.datastore import ModbusServerContext, ModbusDeviceContext, ModbusSequentialDataBlock
from pymodbus.pdu.device import ModbusDeviceIdentification
import threading
import time
import struct
import math
import random

IP_ADDRESS = "0.0.0.0"
PORT = 5020
NUM_SLAVES = 19
# The energy meter can communicate with Modbus ® master devices on an RS-485 network. Use terminal points 7 and
# 8 to connect to the RS-485 network.
# The factory-set Modbus® parameters are as follows:
# • Modbus ® address 001
# • Baud rate 9600
# • 8 data bits
# • Parity: Even
# • 1 stop bit
# The baud rate can be changed to 115200, 56700, 38400, 19200, 9600, 4800, 2400, 1200, 600 and 300 baud.
# Parity can be set to even, odd and none. Data and stop bits cannot be changed.

def float_to_regs(value):
    return list(struct.unpack(">HH", struct.pack(">f", value)))

def int32_to_regs(value):
    return list(struct.unpack(">HH", struct.pack(">i", value)))

def int16_to_reg(value):
    return [value & 0xFFFF]

hr_data = [0] * 65536

def update_registers():
    tick = 0
    energy = 0.0
    while True:
        # Simulated WAGO energy meter Modbus registers (excerpt and extended list from page 33 onward)
        hr_data[16384:16386] = [0x1234, 0x5678]  # serial number (HEX)
        hr_data[16386:16387] = [0xABCD]          # Meter code (HEX)
        hr_data[16387:16388] = int16_to_reg(1)   # Modbus ID (Signed)
        hr_data[16388:16389] = int16_to_reg(6)   # Baud rate (Signed)
        hr_data[16389:16391] = float_to_regs(1.0)  # Protocol version (Float)
        hr_data[16391:16393] = float_to_regs(1.0)  # Software Version (Float)
        hr_data[16393:16395] = float_to_regs(1.0)  # Hardware version (Float)
        hr_data[16395:16396] = int16_to_reg(5)     # Meter amp (Signed)
        hr_data[16396:16397] = [0x0001]            # CT ratio (HEX)
        hr_data[16397:16399] = float_to_regs(1000.0)  # S0 pulse rate (Float)
        hr_data[16399:16400] = int16_to_reg(3)     # Combinations code (Signed)
        hr_data[16400:16401] = [0x000A]            # LCD rolling time (HEX)
        hr_data[16401:16402] = int16_to_reg(1)     # Parity (Signed)
        hr_data[16402:16403] = [ord('F')]          # L1 current direction (ASCII)
        hr_data[16403:16404] = [ord('F')]          # L2 current direction (ASCII)
        hr_data[16404:16405] = [ord('F')]          # L3 current direction (ASCII)
        hr_data[16406:16407] = int16_to_reg(0)     # Power-down counter (Signed)
        hr_data[16407:16408] = int16_to_reg(0)     # Current quadrant (Signed)
        hr_data[16408:16409] = int16_to_reg(0)     # L1 quadrant (Signed)
        hr_data[16409:16410] = int16_to_reg(0)     # L2 quadrant (Signed)
        hr_data[16410:16411] = int16_to_reg(0)     # L3 quadrant (Signed)
        hr_data[16411:16413] = [0x0000, 0x0000]    # Checksum (HEX)
        hr_data[16413:16415] = [0x0000, 0x0000]    # Active status word (HEX)
        hr_data[16415:16417] = int32_to_regs(1999) # CT ratio (Signed)
        hr_data[16417:16419] = int32_to_regs(10)   # S0 pulse width (Signed)
        hr_data[16418:16419] = [0x0001]            # S0 pulse type (HEX)
        hr_data[16419:16421] = [0x0000, 0x0000]    # Checksum 2 (HEX)
        hr_data[16422:16423] = int16_to_reg(1)     # Data type (Signed)
        hr_data[16434:16435] = int16_to_reg(0)     # Screen direction (Signed)
        hr_data[16435:16436] = int16_to_reg(1)     # OBIS code ON/OFF (Signed)

        # Eksempel på hvordan du setter opp float-registre for måleverdier:
        # Simulerer spenning (230V +/- 2V)
        voltage = 230.0 + math.sin(tick / 20.0) * 2.0
        hr_data[20480:20482] = float_to_regs(voltage)   # Voltage
        hr_data[20482:20484] = float_to_regs(voltage + 1)   # L1 voltage
        hr_data[20484:20486] = float_to_regs(voltage + 2)   # L2 voltage
        hr_data[20486:20488] = float_to_regs(voltage + 3)   # L3 voltage
        # Simulerer frekvens (50Hz +/- 0.05Hz)
        freq = 50.0 + math.sin(tick / 50.0) * 0.05
        hr_data[20488:20490] = float_to_regs(freq)   # Frequency
        # Simulerer strøm (100A +/- 2A)
        current = 100.0 + math.sin(tick / 15.0) * 2.0 + random.uniform(-0.2, 0.2)        
        hr_data[20490:20492] = float_to_regs(current + 15.0)    # Current
        hr_data[20492:20494] = float_to_regs(current + 5.1)     # L1 current
        hr_data[20494:20496] = float_to_regs(current + 4.8)     # L2 current
        hr_data[20496:20498] = float_to_regs(current + 4.9)     # L3 current
        # Simulerer aktiv effekt (kW)
        active_power = voltage * current * 0.9 / 1000.0  # Power factor 0.9
        hr_data[20498:20500] = float_to_regs(active_power)     # Total active power
        hr_data[20500:20502] = float_to_regs(active_power - 1)     # L1 active power
        hr_data[20502:20504] = float_to_regs(active_power + 1)     # L2 active power
        hr_data[20504:20506] = float_to_regs(active_power - 2)     # L3 active power
        hr_data[20506:20508] = float_to_regs(0.5)     # Total reactive power
        hr_data[20508:20510] = float_to_regs(0.2)     # L1 reactive power
        hr_data[20510:20512] = float_to_regs(0.2)     # L2 reactive power
        hr_data[20512:20514] = float_to_regs(0.1)     # L3 reactive power
        hr_data[20514:20516] = float_to_regs(4.0)     # Total apparent power
        hr_data[20516:20518] = float_to_regs(1.3)     # L1 apparent power
        hr_data[20518:20520] = float_to_regs(1.4)     # L2 apparent power
        hr_data[20520:20522] = float_to_regs(1.3)     # L3 apparent power
        hr_data[20522:20524] = float_to_regs(0.95)    # Power factor
        hr_data[20524:20526] = float_to_regs(0.96)    # L1 power factor
        hr_data[20526:20528] = float_to_regs(0.95)    # L2 power factor
        hr_data[20528:20530] = float_to_regs(0.94)    # L3 power factor
        hr_data[20530:20532] = float_to_regs(400.0)   # L1-L2 voltage
        hr_data[20532:20534] = float_to_regs(399.8)   # L1-L3 voltage
        hr_data[20534:20536] = float_to_regs(400.1)   # L2-L3 voltage
        # Simulerer energi (kWh), øker over tid
        energy += active_power * (2.0 / 3600.0)  # Oppdateres hvert 2. sekund
        hr_data[24576:24578] = float_to_regs(active_power)  # Total active energy
        hr_data[24578:24580] = float_to_regs(100.0)  # T1 Total active energy
        hr_data[24580:24582] = float_to_regs(101.0)  # T2 Total active energy
        hr_data[24582:24584] = float_to_regs(102.0)  # L1 Total active energy
        hr_data[24584:24586] = float_to_regs(103.0)  # L2 Total active energy
        hr_data[24586:24588] = float_to_regs(104.0)  # L3 Total active energy
        hr_data[24588:24590] = float_to_regs(105.0)  # Active energy import
        hr_data[24590:24592] = float_to_regs(106.0)  # T1 Active energy import
        hr_data[24592:24594] = float_to_regs(107.0)  # T2 Active energy import
        hr_data[24594:24596] = float_to_regs(108.0)  # L1 Active energy import
        hr_data[24596:24598] = float_to_regs(109.0)  # L2 Active energy import
        hr_data[24598:24600] = float_to_regs(110.0)  # L3 Active energy import
        hr_data[24600:24602] = float_to_regs(111.0)  # Active energy export
        hr_data[24602:24604] = float_to_regs(112.0)  # T1 Active energy export
        hr_data[24604:24606] = float_to_regs(113.0)  # T2 Active energy export
        hr_data[24606:24608] = float_to_regs(114.0)  # L1 Active energy export
        hr_data[24608:24610] = float_to_regs(115.0)  # L2 Active energy export
        hr_data[24610:24612] = float_to_regs(116.0)  # L3 Active energy export
        hr_data[24612:24614] = float_to_regs(117.0)  # Total reactive energy
        hr_data[24614:24616] = float_to_regs(118.0)  # T1 Total reactive energy
        hr_data[24616:24618] = float_to_regs(119.0)  # T2 Total reactive energy
        hr_data[24618:24620] = float_to_regs(100.1)  # L1 Total reactive energy
        hr_data[24620:24622] = float_to_regs(100.2)  # L2 Total reactive energy
        hr_data[24622:24624] = float_to_regs(100.3)  # L3 Total reactive energy
        hr_data[24624:24626] = float_to_regs(100.4)  # Reactive energy import
        hr_data[24626:24628] = float_to_regs(100.5)  # T1 Reactive energy import
        hr_data[24628:24630] = float_to_regs(100.6)  # T2 Reactive energy import
        hr_data[24630:24632] = float_to_regs(100.7)  # L1 Reactive energy import
        hr_data[24632:24634] = float_to_regs(100.8)  # L2 Reactive energy import
        hr_data[24634:24636] = float_to_regs(100.9)  # L3 Reactive energy import
        hr_data[24636:24638] = float_to_regs(101.1)  # Reactive energy export
        hr_data[24638:24640] = float_to_regs(101.2)  # T1 Reactive energy export
        hr_data[24640:24642] = float_to_regs(101.3)  # T2 Reactive energy export
        hr_data[24642:24644] = float_to_regs(101.4)  # L1 Reactive energy export
        hr_data[24644:24646] = float_to_regs(101.5)  # L2 Reactive energy export
        hr_data[24646:24648] = float_to_regs(101.6)  # L3 Reactive energy export
        hr_data[24648]       = int16_to_reg(0)    # Tariff (Signed, 2 reg)
        hr_data[24649:24651] = float_to_regs(0.0)  # Resettable day register
        hr_data[24651:24653] = float_to_regs(0.0)  # T3 Total active energy
        hr_data[24653:24655] = float_to_regs(0.0)  # T4 Total active energy
        hr_data[24655:24657] = float_to_regs(0.0)  # T3 Import active energy
        hr_data[24657:24659] = float_to_regs(0.0)  # T4 Import active energy
        hr_data[24659:24661] = float_to_regs(0.0)  # T3 Export active energy
        hr_data[24661:24663] = float_to_regs(0.0)  # T4 Export active energy
        hr_data[24663:24665] = float_to_regs(0.0)  # T3 Total reactive energy
        hr_data[24665:24667] = float_to_regs(0.0)  # T4 Total reactive energy
        hr_data[24667:24669] = float_to_regs(0.0)  # T3 Import reactive energy
        hr_data[24669:24671] = float_to_regs(0.0)  # T4 Import reactive energy
        hr_data[24671:24673] = float_to_regs(0.0)  # T3 Export reactive energy
        hr_data[24673:24675] = float_to_regs(0.0)  # T4 Export reactive energy
        hr_data[24675:24677] = float_to_regs(0.0)  # Import inductive reactive energy in Q1 (total)
        hr_data[24677:24679] = float_to_regs(0.0)  # Import inductive reactive energy in Q1 (T1)
        hr_data[24679:24681] = float_to_regs(0.0)  # Import inductive reactive energy in Q1 (T2)
        hr_data[24681:24683] = float_to_regs(0.0)  # Import inductive reactive energy in Q1 (T3)
        hr_data[24683:24685] = float_to_regs(0.0)  # Import inductive reactive energy in Q1 (T4)
        hr_data[24685:24687] = float_to_regs(0.0)  # Import capacitive reactive energy in Q2 (total)
        hr_data[24687:24689] = float_to_regs(0.0)  # Import capacitive reactive energy in Q2 (T1)
        hr_data[24689:24691] = float_to_regs(0.0)  # Import capacitive reactive energy in Q2 (T2)
        hr_data[24691:24693] = float_to_regs(0.0)  # Import capacitive reactive energy in Q2 (T3)
        hr_data[24693:24695] = float_to_regs(0.0)  # Import capacitive reactive energy in Q2 (T4)
        hr_data[24695:24697] = float_to_regs(0.0)  # Export inductive reactive energy in Q3 (total)
        hr_data[24697:24699] = float_to_regs(0.0)  # Export inductive reactive energy in Q3 (T1)
        hr_data[24699:24701] = float_to_regs(0.0)  # Export inductive reactive energy in Q3 (T2)
        hr_data[24701:24703] = float_to_regs(0.0)  # Export inductive reactive energy in Q3 (T3)
        hr_data[24703:24705] = float_to_regs(0.0)  # Export inductive reactive energy in Q3 (T4)
        hr_data[24705:24707] = float_to_regs(0.0)  # Export capacitive reactive energy in Q4 (total)
        hr_data[24707:24709] = float_to_regs(0.0)  # Export capacitive reactive energy in Q4 (T1)
        hr_data[24709:24711] = float_to_regs(0.0)  # Export capacitive reactive energy in Q4 (T2)
        hr_data[24711:24713] = float_to_regs(0.0)  # Export capacitive reactive energy in Q4 (T3)
        hr_data[24713:24715] = float_to_regs(0.0)  # Export capacitive reactive energy in Q4 (T4)
        hr_data[24715:24717] = float_to_regs(0.0)  # Resettable day register L1
        hr_data[24717:24719] = float_to_regs(0.0)  # Resettable day register L2
        hr_data[24719:24721] = float_to_regs(0.0)  # Resettable day register L3

        # Oppdater L1/L2/L3 med litt variasjon
        for i, base in enumerate([20482, 20484, 20486]):  # L1, L2, L3 voltage
            hr_data[base:base+2] = float_to_regs(voltage + random.uniform(-1, 1))
        for i, base in enumerate([20492, 20494, 20496]):  # L1, L2, L3 current
            hr_data[base:base+2] = float_to_regs(current + random.uniform(-0.5, 0.5))

        # Oppdater alle slaver
        for unit in range(1, NUM_SLAVES + 1):
            context[unit].setValues(3, 0, hr_data)
            context[unit].setValues(4, 0, hr_data)
        tick += 1
        time.sleep(2)

device_contexts = {
    unit: ModbusDeviceContext(
        hr=ModbusSequentialDataBlock(0, hr_data.copy()),
        ir=ModbusSequentialDataBlock(0, hr_data.copy())
    )
    for unit in range(1, NUM_SLAVES + 1) # Creates IDs
}
if NUM_SLAVES == 1:
    context = ModbusServerContext(devices=device_contexts, single=True)
else:
    context = ModbusServerContext(devices=device_contexts, single=False)
    
identity = ModbusDeviceIdentification()
identity.VendorName = "WAGO"
identity.ProductCode = "EM340"
identity.ProductName = "WAGO Energy Meter"
identity.ModelName = "750-494"
identity.MajorMinorRevision = "1.0"

if __name__ == "__main__":
    threading.Thread(target=update_registers, daemon=True).start()
    print(f"Starting WAGO Energy Meter Modbus slave on {IP_ADDRESS}:{PORT}…")
    StartTcpServer(context=context, identity=identity, address=(IP_ADDRESS, PORT))