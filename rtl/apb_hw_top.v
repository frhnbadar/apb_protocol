`timescale 1ns / 1ps

// ============================================================
// PYNQ-Z2 HARDWARE TOP
//
// Purpose:
//   Provides a simple physical interface for testing the
//   APB4 Master-Slave system on the PYNQ-Z2.
//
// Board interface:
//
//   Clock:
//       125 MHz onboard clock
//
//   BTN0:
//       Reset
//
//   BTN1:
//       Start APB transfer
//
//   BTN2:
//       Read / Write selection
//
//   SW0, SW1:
//       Wait-state selection
//
//   LED0:
//       PSEL
//
//   LED1:
//       PENABLE
//
//   LED2:
//       PREADY
//
//   LED3:
//       PWRITE
//
// ============================================================

module apb_hw_top (

    // ========================================================
    // PYNQ-Z2 INPUTS
    // ========================================================

    input  wire       clk,

    input  wire       reset_btn,
    input  wire       transfer_btn,
    input  wire       write_btn,

    input  wire [1:0] wait_states,

    // ========================================================
    // PYNQ-Z2 OUTPUTS
    // ========================================================

    output wire [3:0] led

);


    // ========================================================
    // INTERNAL APB SYSTEM SIGNALS
    // ========================================================

    wire        PRESETn;

    wire [3:0]  wait_states_full;

    wire        transfer;
    wire        SWRITE;

    wire [31:0] SADDR;
    wire [31:0] SWDATA;
    wire [3:0]  SSTRB;
    wire [2:0]  SPROT;

    wire [31:0] SRDATA;
    wire        SSLVERR;

    // APB bus
    wire        PSEL;
    wire        PENABLE;
    wire        PWRITE;

    wire [31:0] PADDR;
    wire [31:0] PWDATA;
    wire [3:0]  PSTRB;
    wire [2:0]  PPROT;

    wire        PREADY;
    wire        PSLVERR;
    wire [31:0] PRDATA;


    // ========================================================
    // RESET
    //
    // APB uses active-low PRESETn.
    //
    // PYNQ-Z2 BTN0 is treated as active-high here:
    //
    // BTN0 released -> reset_btn = 0 -> PRESETn = 1
    // BTN0 pressed  -> reset_btn = 1 -> PRESETn = 0
    //
    // ========================================================

    assign PRESETn = ~reset_btn;


    // ========================================================
    // WAIT-STATE CONFIGURATION
    //
    // Physical switches provide two bits.
    //
    // SW1 SW0
    //  0   0  -> 0 wait states
    //  0   1  -> 1 wait state
    //  1   0  -> 2 wait states
    //  1   1  -> 3 wait states
    //
    // Upper two bits are fixed to zero.
    //
    // ========================================================

    assign wait_states_full = {2'b00, wait_states};


    // ========================================================
    // SYSTEM-SIDE REQUEST
    // ========================================================

    // BTN2 selects read/write
    //
    // 0 -> READ
    // 1 -> WRITE

    assign SWRITE = write_btn;


    // Fixed address for hardware demonstration
    assign SADDR = 32'h0000_0000;


    // Fixed write data
    assign SWDATA = 32'h1234_5678;


    // Enable all four byte lanes
    assign SSTRB = 4'b1111;


    // Normal APB protection attributes
    assign SPROT = 3'b000;


    // ========================================================
    // TRANSFER REQUEST
    // ========================================================
    //
    // BTN1 starts an APB transfer.
    //
    // NOTE:
    // This first version intentionally keeps the interface
    // simple. A debouncer/one-shot can be added later.
    //
    // ========================================================

    assign transfer = transfer_btn;


    // ========================================================
    // APB WRAPPER
    // ========================================================

    APB_Wrapper u_APB_Wrapper (

        // ----------------------------------------------------
        // Clock and reset
        // ----------------------------------------------------

        .PCLK        (clk),
        .PRESETn     (PRESETn),

        // ----------------------------------------------------
        // Wait-state configuration
        // ----------------------------------------------------

        .wait_states (wait_states_full),

        // ----------------------------------------------------
        // System-side request
        // ----------------------------------------------------

        .transfer    (transfer),
        .SWRITE      (SWRITE),
        .SADDR       (SADDR),
        .SWDATA      (SWDATA),
        .SSTRB       (SSTRB),
        .SPROT       (SPROT),

        // ----------------------------------------------------
        // System-side response
        // ----------------------------------------------------

        .SRDATA      (SRDATA),
        .SSLVERR     (SSLVERR),

        // ----------------------------------------------------
        // APB bus
        // ----------------------------------------------------

        .PSEL        (PSEL),
        .PENABLE     (PENABLE),
        .PWRITE      (PWRITE),
        .PADDR       (PADDR),
        .PWDATA      (PWDATA),
        .PSTRB       (PSTRB),
        .PPROT       (PPROT),

        // ----------------------------------------------------
        // APB response
        // ----------------------------------------------------

        .PREADY      (PREADY),
        .PSLVERR     (PSLVERR),
        .PRDATA      (PRDATA)

    );


    // ========================================================
    // LED STATUS
    // ========================================================

    // LED0 = PSEL
    assign led[0] = PSEL;

    // LED1 = PENABLE
    assign led[1] = PENABLE;

    // LED2 = PREADY
    assign led[2] = PREADY;

    // LED3 = PWRITE
    assign led[3] = PWRITE;


endmodule