# wagoEdgeStart

Scripts and examples to help you get started with a WAGO Edge Computer and WAGO controllers.

## Get started

Log in to the machine as a normal user with sudo rights, and run:

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/espenbo/wagoEdgeStart/main/setupEdgeComputer/setup_edge_computer.sh)
```

Choose **1) Recommended setup** on a new machine. See [setupEdgeComputer](setupEdgeComputer/Readme.md) for all programs, and for what to do if you only have the root user.

## Contents

| Folder | Contents |
|---|---|
| [setupEdgeComputer](setupEdgeComputer/Readme.md) | Menu for installing programs on the machine, and for removing them again |
| [WagoLogin](WagoLogin) | Login script, installed from the menu |
| [addNATFirewall](addNATFirewall/README.md) | NAT and firewall script |
| [addusers](addusers/README.md) | Add users from a CSV file |
| [hd_speed_test](hd_speed_test/README.md) | Disk speed test for PC and PLC |
| [modbus_slaves](modbus_slaves/README.md) | Simulated Modbus slaves for SolarLog and WAGO energy meters |
| [TeltonikaRouter](TeltonikaRouter/README.md) | Send SMS and read status from Teltonika routers, from Ignition, bash, BusyBox and CODESYS |
