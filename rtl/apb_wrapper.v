`timescale 1ns / 1ps

// ============================================================
// APB4 MASTER-SLAVE WRAPPER
//
// Contains:
//   1. APB_Master
//   2. APB_Slave
//
// This module is the reusable APB subsystem.
// For PYNQ-Z2 hardware, use apb_hw_top.v as the Vivado top.
// ============================================================

module APB_Wrapper (

    // ========================================================
    // System-side interface
    // ========================================================

    input  wire        PCLK,
    input  wire        PRESETn,

    input  wire [3:0]  wait_states,

    input  wire        transfer,
    input  wire        SWRITE,

    input  wire [31:0] SADDR,
    input  wire [31:0] SWDATA,
    input  wire [3:0]  SSTRB,
    input  wire [2:0]  SPROT,

    output wire [31:0] SRDATA,
    output wire        SSLVERR,

    // ========================================================
    // APB bus interface
    // ========================================================

    output wire        PSEL,
    output wire        PENABLE,
    output wire        PWRITE,

    output wire [31:0] PADDR,
    output wire [31:0] PWDATA,
    output wire [3:0]  PSTRB,
    output wire [2:0]  PPROT,

    input  wire        PREADY,
    input  wire        PSLVERR,
    input  wire [31:0] PRDATA

);

    // ========================================================
    // APB Master
    // ========================================================

    APB_Master u_APB_Master (

        .PCLK       (PCLK),
        .PRESETn    (PRESETn),

        .transfer   (transfer),
        .SWRITE     (SWRITE),
        .SADDR      (SADDR),
        .SWDATA     (SWDATA),
        .SSTRB      (SSTRB),
        .SPROT      (SPROT),

        .SRDATA     (SRDATA),
        .SSLVERR    (SSLVERR),

        .PSEL       (PSEL),
        .PENABLE    (PENABLE),
        .PWRITE     (PWRITE),
        .PADDR      (PADDR),
        .PWDATA     (PWDATA),
        .PSTRB      (PSTRB),
        .PPROT      (PPROT),

        .PRDATA     (PRDATA),
        .PREADY     (PREADY),
        .PSLVERR    (PSLVERR)
    );


    // ========================================================
    // APB Slave
    // ========================================================

    APB_Slave #(
        .ADDR_BITS(8)
    ) u_APB_Slave (

        .PCLK       (PCLK),
        .PRESETn    (PRESETn),

        .PSEL       (PSEL),
        .PENABLE    (PENABLE),
        .PWRITE     (PWRITE),

        .PADDR      (PADDR),
        .PWDATA     (PWDATA),
        .PSTRB      (PSTRB),
        .PPROT      (PPROT),

        .PREADY     (PREADY),
        .PRDATA     (PRDATA),
        .PSLVERR    (PSLVERR),

        .wait_states(wait_states)
    );

endmodule