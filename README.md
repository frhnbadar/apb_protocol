# APB4 Master–Slave RTL Design

A synthesizable **AMBA APB4 master–slave system** implemented in Verilog, featuring a 3-state APB master FSM, a configurable APB slave with a memory-backed register space, APB4 byte strobes, protection signals, configurable wait states, back-to-back transfers, and a simulation testbench.

The project also contains a **PYNQ-Z2 hardware wrapper** for demonstrating APB bus activity on-board. The hardware wrapper is kept separate from the APB subsystem so that the core APB architecture remains clean and reusable.

> **Important:** The APB design is verified through simulation. The `apb_hw_top.v` module is provided as the FPGA-board integration layer; it should not be considered hardware-validated unless the design has actually been programmed and tested on a PYNQ-Z2.

---

## 1. Project Objectives

This project was developed to understand and implement an APB4 peripheral system from RTL level to FPGA integration.

The main objectives are:

- Implement an APB master using a standard 3-phase FSM.
- Implement an APB slave with a memory-backed storage array.
- Support APB4 write strobes (`PSTRB[3:0]`).
- Support APB protection signals (`PPROT[2:0]`).
- Support configurable slave wait states.
- Support zero-wait and multi-cycle ACCESS transfers.
- Support back-to-back APB transfers without returning to IDLE.
- Verify byte-lane writes and read/write behavior through simulation.
- Verify bus stability during ACCESS and wait-state operation.
- Provide a simple PYNQ-Z2 hardware demonstration wrapper.
- Keep the APB subsystem independent from physical FPGA I/O.

---

## 2. Project Structure

```text
apb_protocol/
│
├── constraint/
│   └── apb_hw_top_constraint.xdc
│
├── docs/
│   └── (architecture diagrams / documentation)
│
├── rtl/
│   ├── apb_hw_top.v
│   ├── apb_master.v
│   ├── apb_slave.v
│   └── apb_wrapper.v
│
├── tb/
│   └── apb_tb.sv
│
├── README.md
└── LICENSE
```

### Directory purpose

| Directory/File | Purpose |
|---|---|
| `rtl/apb_master.v` | APB master FSM and APB request/response handling |
| `rtl/apb_slave.v` | APB4 slave, wait-state generation and 256×32 memory |
| `rtl/apb_wrapper.v` | Connects the master and slave into one APB subsystem |
| `rtl/apb_hw_top.v` | PYNQ-Z2 board-level demonstration wrapper |
| `tb/apb_tb.sv` | Simulation testbench for the APB subsystem |
| `constraint/apb_hw_top_constraint.xdc` | PYNQ-Z2 pin and clock constraints |
| `docs/` | Architecture/state diagrams and supporting documentation |
| `README.md` | Complete project documentation |
| `LICENSE` | Open-source license |

---

## 3. High-Level Architecture

```text
                    System-Side Request
          ┌─────────────────────────────────┐
          │ transfer, SWRITE, SADDR,        │
          │ SWDATA, SSTRB, SPROT             │
          └───────────────┬─────────────────┘
                          │
                          ▼
                ┌───────────────────┐
                │    APB_Wrapper    │
                │                   │
                │ ┌───────────────┐ │
                │ │  APB_Master   │ │
                │ │               │ │
                │ │ IDLE          │ │
                │ │ SETUP         │ │
                │ │ ACCESS        │ │
                │ └───────┬───────┘ │
                │         │         │
                │         │ APB4    │
                │         ▼         │
                │   ┌───────────┐   │
                │   │ APB Slave │   │
                │   │           │   │
                │   │ Wait-State│   │
                │   │ Generator │   │
                │   │           │   │
                │   │ 256×32    │   │
                │   │ Memory    │   │
                │   └───────────┘   │
                └───────────────────┘
                          │
                          ▼
                   SRDATA / SSLVERR
```

The APB wrapper is the logical subsystem. The PYNQ-Z2 wrapper sits above it only when physical FPGA I/O is required.

### FPGA-level hierarchy

```text
PYNQ-Z2
   │
   ▼
apb_hw_top
   │
   ▼
apb_wrapper
   ├── apb_master
   └── apb_slave
```

For RTL/schematic analysis, `apb_wrapper` is the most useful top-level module because it directly exposes the Master–Slave architecture.

---

## 4. APB Master

### Module

```text
APB_Master
```

The master converts a simple system-side request into an APB transaction.

### Master FSM

The master contains three states:

```text
             transfer
   IDLE ─────────────────► SETUP
    ▲                       │
    │                       │ always
    │                       ▼
    └────── ACCESS ◄────────┘
           │
           │ PREADY = 0
           └──────────────► ACCESS

ACCESS completion:

PREADY = 1, transfer = 1  → SETUP
PREADY = 1, transfer = 0  → IDLE
```

### State behavior

#### IDLE

```text
PSEL    = 0
PENABLE = 0
```

No APB transfer is active.

If `transfer=1`, the master moves to `SETUP`.

#### SETUP

```text
PSEL    = 1
PENABLE = 0
```

The APB request is presented and held stable.

The master then moves to `ACCESS`.

#### ACCESS

```text
PSEL    = 1
PENABLE = 1
```

The slave performs the requested operation.

- If `PREADY=0`, the master remains in ACCESS.
- If `PREADY=1` and another transfer is requested, the master returns directly to SETUP.
- If `PREADY=1` and no new transfer is requested, the master returns to IDLE.

This gives the design support for APB back-to-back transfers.

---

## 5. APB Master Signals

| Signal | Direction | Width | Description |
|---|---:|---:|---|
| `PCLK` | Input | 1 | APB clock |
| `PRESETn` | Input | 1 | Active-low reset |
| `transfer` | Input | 1 | Requests a system-side APB transfer |
| `SWRITE` | Input | 1 | `1` = write, `0` = read |
| `SADDR` | Input | 32 | System-side address |
| `SWDATA` | Input | 32 | Write data |
| `SSTRB` | Input | 4 | APB4 byte write strobes |
| `SPROT` | Input | 3 | APB protection attributes |
| `SRDATA` | Output | 32 | Returned read data |
| `SSLVERR` | Output | 1 | Returned slave error |
| `PSEL` | Output | 1 | APB peripheral select |
| `PENABLE` | Output | 1 | APB enable |
| `PWRITE` | Output | 1 | APB read/write direction |
| `PADDR` | Output | 32 | APB address |
| `PWDATA` | Output | 32 | APB write data |
| `PSTRB` | Output | 4 | APB4 byte strobes |
| `PPROT` | Output | 3 | APB protection attributes |
| `PRDATA` | Input | 32 | APB read data |
| `PREADY` | Input | 1 | APB transfer completion |
| `PSLVERR` | Input | 1 | APB slave error |

---

## 6. APB Slave

### Module

```text
APB_Slave #(.ADDR_BITS(8))
```

The slave implements:

- APB4 interface
- 256 words of 32-bit storage
- configurable wait states
- byte-enable writes using `PSTRB`
- combinational read data
- `PSLVERR=0` in the current implementation

### Memory organization

```text
DEPTH = 1 << ADDR_BITS
      = 1 << 8
      = 256 words
```

Each word is 32 bits:

```text
256 × 32-bit
```

The word index is derived from the aligned address bits:

```text
PADDR[ADDR_BITS+1:2]
```

For `ADDR_BITS=8` this becomes:

```text
PADDR[9:2]
```

Therefore the lower two address bits are ignored for word selection.

---

## 7. APB4 Byte Strobes

`PSTRB[3:0]` determines which byte lanes are written.

```text
PSTRB[0] → PWDATA[7:0]
PSTRB[1] → PWDATA[15:8]
PSTRB[2] → PWDATA[23:16]
PSTRB[3] → PWDATA[31:24]
```

For a write, only enabled byte lanes are modified. Disabled byte lanes retain their previous values.

Conceptually:

```text
new_byte = PSTRB ? PWDATA_byte : old_byte
```

This is an important APB4 feature and allows partial-word writes.

### Example

Suppose memory contains:

```text
0x11223344
```

and the master writes:

```text
PWDATA = 0xAABBCCDD
PSTRB  = 4'b0011
```

Then the lower two bytes are replaced while the upper two bytes remain unchanged:

```text
Result = 0x1122CCDD
```

---

## 8. Read Transactions

For reads:

```text
PWRITE = 0
```

The current master drives:

```text
PSTRB = 4'b0000
```

because byte strobes are relevant to writes.

The slave provides `PRDATA` from the selected memory location while the read transfer is active.

When the transfer completes, the master captures `PRDATA` into `SRDATA`.

---

## 9. Wait-State Generator

The slave supports configurable wait states through:

```text
wait_states[3:0]
```

The value is sampled during the APB SETUP phase.

Internally:

```text
ws_lat  = latched wait-state value
wait_cnt = ACCESS-phase counter
```

The completion condition is effectively:

```text
PREADY = PSEL && PENABLE && (wait_cnt >= ws_lat)
```

Therefore the slave can intentionally hold the master in ACCESS for multiple cycles.

### ACCESS duration

For the implemented counter scheme:

```text
ACCESS cycles = wait_states + 1
```

Examples:

| `wait_states` | ACCESS duration |
|---:|---:|
| 0 | 1 cycle |
| 1 | 2 cycles |
| 2 | 3 cycles |
| 3 | 4 cycles |
| 4 | 5 cycles |
| 15 | 16 cycles |

The wait-state value is latched at the beginning of the transfer so that the transaction remains stable while it is executing.

---

## 10. Back-to-Back Transfers

The master supports APB back-to-back operation.

When a transfer completes:

```text
ACCESS → SETUP
```

can occur directly if `transfer` remains asserted.

The bus therefore does not need to return to IDLE between consecutive transfers.

This behavior is useful for burst-like sequences of APB transactions and was explicitly exercised in the testbench.

---

## 11. APB Wrapper

### Module

```text
APB_Wrapper
```

The wrapper connects:

```text
APB_Master ↔ APB4 signals ↔ APB_Slave
```

It does not add another APB protocol FSM. Its purpose is structural integration.

The wrapper connects:

- `PSEL`
- `PENABLE`
- `PWRITE`
- `PADDR`
- `PWDATA`
- `PSTRB`
- `PPROT`
- `PRDATA`
- `PREADY`
- `PSLVERR`

between the master and slave.

The wrapper also exposes the system-side request/response interface.

---

## 12. PYNQ-Z2 Hardware Wrapper

### Module

```text
apb_hw_top
```

`apb_hw_top.v` is a board-level demonstration wrapper around `APB_Wrapper`.

It maps a small number of physical switches/buttons/LEDs to the APB system so that the internal bus activity can be observed on a PYNQ-Z2.

### Hardware interface

The hardware wrapper uses:

| Signal | Purpose |
|---|---|
| `clk` | PYNQ-Z2 125 MHz clock |
| `reset_btn` | Active-high external reset button |
| `transfer_btn` | Starts a transfer |
| `write_btn` | Selects write/read direction |
| `wait_states[1:0]` | Selects a small wait-state value for the demo |
| `led[3:0]` | Displays APB bus status |

The internal APB configuration used by the demonstration wrapper is intentionally simple:

```text
SADDR = 0x00000000
SWDATA = 0x12345678
SSTRB = 4'b1111
SPROT = 3'b000
```

This makes the board demonstration easy to understand while leaving the full APB interface available inside `APB_Wrapper`.

### LED mapping

```text
LED0 → PSEL
LED1 → PENABLE
LED2 → PREADY
LED3 → PWRITE
```

This allows the main APB phases to be observed directly:

```text
IDLE:
PSEL=0, PENABLE=0

SETUP:
PSEL=1, PENABLE=0

ACCESS:
PSEL=1, PENABLE=1
```

### Important hardware note

Mechanical push buttons can bounce. Therefore, pressing `transfer_btn` may produce multiple electrical transitions and potentially multiple transfers.

For a polished hardware demonstration, the button should eventually be passed through:

```text
button → synchronizer → debouncer → one-shot/pulse generator → APB request
```

The core APB RTL does not depend on the debouncer.

---

## 13. PYNQ-Z2 Clock

The PYNQ-Z2 board-level wrapper uses the board's 125 MHz oscillator.

The corresponding XDC constraint is:

```tcl
create_clock -period 8.000 -name sys_clk [get_ports clk]
```

because:

```text
1 / 125 MHz = 8 ns
```

The board-level XDC is stored at:

```text
constraint/apb_hw_top_constraint.xdc
```

---

## 14. Simulation Testbench

### Testbench

```text
tb/apb_tb.sv
```

The testbench verifies the APB subsystem rather than relying only on waveform inspection.

The verification includes tests for:

- APB writes
- APB reads
- `PSTRB` byte-lane behavior
- multiple memory words
- neighboring memory locations
- back-to-back transfers
- unaligned address mapping behavior
- `PPROT` pass-through
- wait states from 1 through 4
- transfers combined with wait states
- constrained-random wait-state values from 0 through 5
- reads with `PSTRB=0`
- APB bus stability during ACCESS
- `PENABLE` only being asserted when `PSEL` is active
- known `PRDATA` at read completion
- expected ACCESS length based on the configured wait states

The testbench therefore checks both functional behavior and important APB timing/protocol properties.

---

## 15. Verification Philosophy

The verification focuses on the following invariants.

### APB phase relationship

```text
PENABLE = 1  → PSEL must also be 1
```

### SETUP behavior

```text
PSEL    = 1
PENABLE = 0
```

### ACCESS behavior

```text
PSEL    = 1
PENABLE = 1
```

### Wait-state behavior

While:

```text
PREADY = 0
```

the master must remain in ACCESS.

### Completion behavior

A transfer completes only when:

```text
PSEL && PENABLE && PREADY
```

is true.

### Back-to-back behavior

A completed transfer can be followed immediately by another SETUP phase without returning to IDLE.

---

## 16. Addressing

The slave uses word-aligned addressing.

With `ADDR_BITS=8`:

```text
Memory words = 256
Word width   = 32 bits
Word index   = PADDR[9:2]
```

This means addresses that differ only in the lowest two bits can map to the same 32-bit word.

For example, conceptually:

```text
0x00000000 → word 0
0x00000001 → word 0
0x00000002 → word 0
0x00000003 → word 0
0x00000004 → word 1
```

This behavior is intentional for the current word-oriented memory implementation.

---

## 17. Error Handling

The current slave implementation drives:

```text
PSLVERR = 0
```

and therefore does not currently generate APB slave errors.

The master still captures the slave error signal into:

```text
SSLVERR
```

This leaves a clean extension point for future error checking, such as invalid addresses or illegal accesses.

---

## 18. Protection Signals

The system-side signal:

```text
SPROT[2:0]
```

is passed through the master to:

```text
PPROT[2:0]
```

The current slave does not implement access-policy checking based on `PPROT`; the signal is preserved for APB4 interface completeness and future extension.

---

## 19. Synthesis and Schematic Viewing

There are two useful ways to inspect the design in Vivado.

### A. RTL/elaborated schematic

Use `APB_Wrapper` as the top module when the goal is to inspect the Master–Slave architecture.

This gives the most direct view of:

```text
APB_Wrapper
 ├── APB_Master
 └── APB_Slave
```

### B. FPGA implementation hierarchy

Use `apb_hw_top` as the synthesis top when the goal is PYNQ-Z2 hardware implementation.

The hierarchy becomes:

```text
apb_hw_top
 └── APB_Wrapper
      ├── APB_Master
      └── APB_Slave
```

If Vivado displays only a high-level block, open/drill into the `APB_Wrapper` hierarchy to inspect the Master and Slave.

If preserving module hierarchy in the synthesized schematic is important, use a synthesis hierarchy setting that preserves hierarchy rather than aggressively flattening it.

---

## 20. Recommended Vivado Setup

### For simulation

Add:

```text
RTL:
    rtl/apb_master.v
    rtl/apb_slave.v
    rtl/apb_wrapper.v

Simulation:
    tb/apb_tb.sv
```

Use:

```text
apb_tb
```

as the simulation top.

### For schematic/synthesis of APB architecture

Use:

```text
apb_wrapper
```

as the top module.

### For PYNQ-Z2 hardware

Use:

```text
apb_hw_top
```

as the synthesis/implementation top and add:

```text
constraint/apb_hw_top_constraint.xdc
```

---

## 21. Expected APB Transaction Timing

A normal transaction follows:

```text
        SETUP              ACCESS
          │                  │
PSEL    ──┐──────────────────┐────
          │                  │
PENABLE ──┴──────────┐       │
                     └───────┘

PREADY                   ─────┐
                              └── completion
```

More explicitly:

```text
IDLE
  │
  │ transfer
  ▼
SETUP
  │
  │ next clock
  ▼
ACCESS
  │
  ├── PREADY=0 → remain ACCESS
  │
  └── PREADY=1
        │
        ├── transfer=1 → SETUP
        │
        └── transfer=0 → IDLE
```

---

## 22. Design Decisions

### Why a separate `APB_Wrapper`?

The wrapper separates the reusable APB subsystem from board-specific I/O.

This prevents PYNQ-Z2-specific buttons, switches, LEDs, and constraints from becoming part of the actual APB master/slave design.

### Why a separate `apb_hw_top`?

`APB_Wrapper` exposes the complete APB/system interface and therefore has far more signals than are practical to connect directly to physical FPGA pins.

`apb_hw_top` reduces this to a small demonstration interface suitable for the PYNQ-Z2.

### Why use a memory-backed slave?

A memory array makes read/write behavior easy to observe and provides a useful foundation for later conversion into a register-mapped peripheral.

### Why support wait states?

Real peripherals can require multiple cycles to complete a transfer. The configurable wait-state generator demonstrates how APB holds the ACCESS phase until the slave is ready.

---

## 23. Limitations / Future Improvements

The current implementation is intentionally educational and compact. Possible future improvements include:

- Add button synchronizers and debouncing to `apb_hw_top`.
- Add a one-shot transfer pulse generator.
- Add real PYNQ-Z2 hardware validation.
- Add a richer register map instead of a simple memory array.
- Generate `PSLVERR` for invalid or protected accesses.
- Implement `PPROT` access checking.
- Add formal APB protocol assertions.
- Add SystemVerilog assertions for master/slave timing rules.
- Add functional coverage for APB states and transaction combinations.
- Add randomized addresses, data, strobes and read/write sequences.
- Add a configurable memory size parameter.
- Add a proper APB peripheral/register-file example.
- Add waveform screenshots and synthesis reports under `docs/`.
- Add resource-utilization and timing results after FPGA implementation.

---

## 24. Key Learning Outcomes

This project demonstrates practical understanding of:

- RTL design
- finite-state machines
- synchronous digital design
- APB protocol phases
- APB4 byte strobes
- APB protection signals
- ready/wait-state handshaking
- back-to-back bus transfers
- memory-mapped storage
- byte-lane merging
- Verilog module hierarchy
- SystemVerilog testbench development
- simulation-based verification
- Vivado synthesis
- RTL and synthesized schematic inspection
- FPGA top-level integration
- PYNQ-Z2 constraints and clocking

It also demonstrates the distinction between:

```text
Reusable RTL subsystem
        vs.
Board-specific hardware wrapper
```

which is an important design practice in FPGA development.

---

## 25. Tools

The project is intended for an FPGA/RTL workflow using tools such as:

- AMD/Xilinx Vivado
- Verilog/SystemVerilog simulator
- PYNQ-Z2 development board
- Git/GitHub for version control

The exact simulator is not required by the RTL itself; the testbench should be run with a simulator supported by the selected Vivado/project workflow.

---

## 26. How to Use

### Step 1 — Clone the repository

```bash
git clone <YOUR_REPOSITORY_URL>
cd apb_protocol
```

### Step 2 — Create a Vivado project

Add:

```text
rtl/apb_master.v
rtl/apb_slave.v
rtl/apb_wrapper.v
```

and, for simulation:

```text
tb/apb_tb.sv
```

### Step 3 — Run simulation

Set:

```text
apb_tb
```

as the simulation top and run the behavioral simulation.

### Step 4 — Inspect the APB architecture

Set:

```text
apb_wrapper
```

as the design top if the primary goal is to inspect the Master/Slave schematic.

### Step 5 — Program the PYNQ-Z2

For board implementation, use:

```text
rtl/apb_hw_top.v
constraint/apb_hw_top_constraint.xdc
```

and set:

```text
apb_hw_top
```

as the synthesis top.

Generate the bitstream and program the FPGA only after checking synthesis, implementation, timing and I/O constraints.

---

## 27. Repository Status

Current project scope:

- [x] APB master FSM
- [x] APB slave
- [x] APB wrapper
- [x] APB4 `PSTRB`
- [x] `PPROT` pass-through
- [x] Configurable wait states
- [x] Back-to-back transfers
- [x] Memory-backed storage
- [x] Byte-lane write merge
- [x] Simulation testbench
- [x] PYNQ-Z2 hardware wrapper
- [x] PYNQ-Z2 XDC
- [ ] Hardware validation report
- [ ] Button debouncer / one-shot
- [ ] Formal verification
- [ ] Full APB peripheral register map

---

## 28. License

This project is released under the **MIT License**. See [`LICENSE`](LICENSE) for the complete license text.

---

## Author

**Farhan Badar**

B.Tech Electronics — VLSI Design & Technology  
Jamia Millia Islamia

GitHub: `frhnbadar`

