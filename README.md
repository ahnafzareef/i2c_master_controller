# I2C Master Controller

An I2C master written in Verilog for the Arty S7-25 FPGA

## How it works

Each bit is split into **four clock phases**, so every SCL and SDA edge gets its own phase. SDA only changes while SCL is low and is sampled while SCL is high, which meets setup/hold timing by design instead of tuned delays.


The bus is **open-drain**: the master only ever pulls a line low or releases it to the pull-up. It never drives high, so it can share the bus without contention. 

Supported commands: **start, write, read, stop, restart**. Each byte transfer is 9 bits (8 data + acknowledge).

## Files

| File | Description |
|------|-------------|
| `i2c_master.v` | The I2C master (FSM + datapath) |
| `i2c_master_tb.v` | Self-checking testbench with a behavioral slave model |

## Testing

The testbench includes a fake I2C slave that address-matches, ACKs, and returns data on reads. It runs three tests with automatic pass/fail checks:

1. **Write** — start, address + W, two data bytes, stop
2. **Wrong address** — expects a NACK from the bus
3. **Read** — reads a byte back and checks it matches the slave's data

```
iverilog -g2012 -o sim i2c_master.v i2c_master_tb.v
vvp sim
```

Expected output: `RESULT: 6 passed, 0 failed`

## Hardware

- **Board:** Digilent Arty S7-25 (Spartan-7, xc7s25csga324-1)
- **Toolchain:** Vivado 2025.2
- **Integration:** deployed as a memory-mapped peripheral on a MicroBlaze SoC with a C driver (Currently finishing the driver with MicroBlaze SOC)

## Notes

The clock divider sets the SCL rate: `dvsr = f_sys / (4 × f_i2c)`, 4 comes from the four phases per bit.
