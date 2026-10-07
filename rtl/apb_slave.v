`timescale 1ns/1ps
// ============================================================
// APB Slave Module
// Responds to APB transfers with an internal cache memory.
// Supports all PSTRB combinations for partial word writes.
// ============================================================
module APB_Slave #(
    parameter MEM_WIDTH = 32,   // Width of each memory word in bits
    parameter MEM_DEPTH = 1024  // Number of addressable memory locations
)(
    // --- APB Bus Inputs (from Master) ---
    input        PSEL,
    input        PENABLE,
    input        PWRITE,
    input [31:0] PADDR,
    input [31:0] PWDATA,
    input [3:0]  PSTRB,
    input [2:0]  PPROT,         // Protection signals (received, not used)

    // --- APB Clock and Reset ---
    input        PCLK,
    input        PRESETn,       // Active-LOW reset

    // --- APB Slave Outputs (to Master) ---
    output reg [31:0] PRDATA,
    output            PREADY,
    output reg        PSLVERR
);

    reg [MEM_WIDTH-1:0] Cache [MEM_DEPTH-1:0];

    // Transfer happens only in ACCESS phase (PSEL && PENABLE)
    always @(posedge PCLK) begin
        if (~PRESETn) begin
            PSLVERR <= 0;
            PRDATA  <= 0;
        end
        else if (PSEL && PENABLE) begin

            if (PWRITE) begin
                case (PSTRB)
                    4'b0001: Cache[PADDR] <= {{24{PWDATA[7]}},  PWDATA[7:0]};
                    // FIX: replication 24 -> 16 (was 40 bits wide, silently truncated; value unchanged)
                    4'b0010: Cache[PADDR] <= {{16{PWDATA[15]}}, PWDATA[15:8],  8'h00};
                    4'b0011: Cache[PADDR] <= {{16{PWDATA[15]}}, PWDATA[15:0]};
                    // FIX: replication 24 -> 16 (same reason)
                    4'b0100: Cache[PADDR] <= {{16{PWDATA[23]}}, PWDATA[23:16], 8'h00};
                    // FIX: replication 16 -> 8 (same reason)
                    4'b0101: Cache[PADDR] <= {{8{PWDATA[23]}},  PWDATA[23:16], 8'h00, PWDATA[7:0]};
                    4'b0110: Cache[PADDR] <= {{8{PWDATA[23]}},  PWDATA[23:8],  8'h00};
                    4'b0111: Cache[PADDR] <= {{8{PWDATA[23]}},  PWDATA[23:0]};
                    4'b1000: Cache[PADDR] <= {PWDATA[31:24], 24'h000000};
                    4'b1001: Cache[PADDR] <= {PWDATA[31:24], 16'h0000, PWDATA[7:0]};
                    // FIX (real bug): was PWDATA[31:23] -> 33-bit concat, MSB dropped, byte 3 came out shifted by 1 bit
                    4'b1010: Cache[PADDR] <= {PWDATA[31:24], 8'h00, PWDATA[15:8], 8'h00};
                    // FIX (real bug): same [31:23] typo
                    4'b1011: Cache[PADDR] <= {PWDATA[31:24], 8'h00, PWDATA[15:0]};
                    4'b1100: Cache[PADDR] <= {PWDATA[31:16], 16'h0000};
                    4'b1101: Cache[PADDR] <= {PWDATA[31:16], 8'h00, PWDATA[7:0]};
                    4'b1110: Cache[PADDR] <= {PWDATA[31:8],  8'h00};
                    4'b1111: Cache[PADDR] <= PWDATA[31:0];
                    default: Cache[PADDR] <= 32'h00000000; // PSTRB=0000 lands here (see notes: spec says no-op)
                endcase
                PSLVERR <= 0;
            end
            else begin
                // Per APB spec PSTRB must be 0 on reads; otherwise flag a slave error.
                if (PSTRB != 0) begin
                    PSLVERR <= 1;
                end
                else begin
                    PRDATA  <= Cache[PADDR];
                    PSLVERR <= 0;
                end
            end
        end
    end

    // Zero-wait-state slave
    assign PREADY = (PSEL && PENABLE) ? 1 : 0;

endmodule