`timescale 1ns/1ps
// ============================================================
// APB Master Module
// Drives the APB bus based on external system inputs.
// Implements the 3-state FSM: IDLE -> SETUP -> ACCESS
// ============================================================
module APB_Master (
    // --- External System Inputs ---
    input SWRITE,              // System write enable: 1=write, 0=read
    input [31:0] SADDR,        // System address to transfer on APB
    input [31:0] SWDATA,       // System write data
    input [3:0]  SSTRB,        // System write strobe: each bit enables one byte lane
    input [2:0]  SPROT,        // System protection type (privilege/security/instruction)
    input        transfer,     // Handshake from system: 1 = initiate/continue a transfer

    // --- APB Bus Master Outputs ---
    output reg        PSEL,    // Peripheral Select: activates the target slave
    output reg        PENABLE, // Enable: goes high in ACCESS state to complete transfer
    output reg        PWRITE,  // Write control: 1=write, 0=read (stable across SETUP+ACCESS)
    output reg [31:0] PADDR,   // APB Address bus (stable across SETUP+ACCESS)
    output reg [31:0] PWDATA,  // APB Write Data (stable across SETUP+ACCESS)
    output reg [3:0]  PSTRB,   // APB Write Strobe: which byte lanes are active
    output reg [2:0]  PPROT,   // APB Protection signals

    // --- APB Clock and Reset ---
    input PCLK,                // APB clock: all APB transfers are synchronous to this
    input PRESETn,             // Active-LOW reset

    // --- APB Slave Response Inputs ---
    input PREADY,              // Slave ready: 1=slave can complete transfer, 0=insert wait states
    input PSLVERR              // Slave error: 1=transfer failed (optional signal per APB spec)
);

    // --- FSM State Encoding ---
    localparam IDLE   = 2'b00, // No transfer in progress, bus is idle
               SETUP  = 2'b01, // First cycle: PSEL asserted, signals driven, PENABLE=0
               ACCESS = 2'b10; // Second+ cycle: PENABLE asserted, waiting for PREADY

    (* fsm_encoding = "one_hot" *)
    reg [1:0] ns, cs; // ns = next state, cs = current state

    // -------------------------------------------------------
    // STATE MEMORY (Sequential Block)
    // -------------------------------------------------------
    always @(posedge PCLK, negedge PRESETn) begin
        if (~PRESETn)
            cs <= IDLE;   // Asynchronous reset: go to IDLE immediately when reset asserted
        else
            cs <= ns;     // On each rising clock edge, advance to next state
    end

    // -------------------------------------------------------
    // NEXT STATE LOGIC (Combinational Block)
    // -------------------------------------------------------
    always @(*) begin
        case (cs)
            IDLE : begin
                if (transfer)
                    ns = SETUP;
                else
                    ns = IDLE;
            end

            SETUP : begin
                // SETUP always lasts exactly ONE clock cycle per APB spec.
                ns = ACCESS;
            end

            ACCESS : begin
                if (PREADY && !transfer)
                    ns = IDLE;       // Transfer done, no new transfer pending -> go idle
                else if (PREADY && transfer)
                    ns = SETUP;      // Transfer done, new transfer pending -> back to SETUP
                else
                    ns = ACCESS;     // Slave not ready yet -> stay in ACCESS (wait state)
            end

            default : ns = IDLE;    // Safety default for synthesis
        endcase
    end

    // -------------------------------------------------------
    // OUTPUT LOGIC (Combinational Block)
    // -------------------------------------------------------
    always @(*) begin
        if (~PRESETn) begin
            PSEL    = 0;
            PENABLE = 0;
            PWRITE  = 0;
            PADDR   = 0;
            PWDATA  = 0;
            PSTRB   = 0;
            PPROT   = 0;
        end
        else begin
            case (cs)
                IDLE : begin
                    PSEL    = 0;
                    PENABLE = 0;
                    // PWRITE, PADDR, PWDATA etc. retain last values (harmless since PSEL=0)
                end

                SETUP : begin
                    PSEL    = 1;
                    PENABLE = 0;
                    PWRITE  = SWRITE;  // Latch write/read direction from system
                    PADDR   = SADDR;   // Latch target address from system
                    PWDATA  = SWDATA;  // Latch write data from system
                    PSTRB   = SSTRB;   // Latch byte strobes from system
                    PPROT   = SPROT;   // Latch protection bits from system
                end

                ACCESS : begin
                    PSEL    = 1;
                    PENABLE = 1;
                    // PWRITE, PADDR, PWDATA, PSTRB, PPROT hold their values
                end
            endcase
        end
    end

endmodule