`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09.09.2026 18:13:14
// Design Name: 
// Module Name: APB_MASTER
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module APB_MASTER #(
    parameter ADDR_WIDTH    = 64,
    parameter DATA_WIDTH    = 64,
    parameter STRB_WIDTH    = DATA_WIDTH/8,
    parameter ENABLE_PARITY = 1
) (
    input                        SWRITE,
    input  [ADDR_WIDTH-1:0]      SADDR,
    input  [DATA_WIDTH-1:0]      SWDATA,
    input  [STRB_WIDTH-1:0]      SSTRB,
    input  [2:0]                 SPROT,
    input                        transfer,

    output reg                   PSEL,
    output reg                   PENABLE,
    output reg                   PWRITE,
    output reg [ADDR_WIDTH-1:0]  PADDR,
    output reg [DATA_WIDTH-1:0]  PWDATA,
    output reg [STRB_WIDTH-1:0]  PSTRB,
    output reg [2:0]             PPROT,

    output reg                   PWAKEUP,

    output reg                   PADDRPAR,
    output reg                   PWDATAPAR,
    output reg                   PSTRBPAR,
    output reg                   PPROTPAR,

    input  [DATA_WIDTH-1:0]      PRDATA, // Added missing read data bus
    input                        PCLK,
    input                        PRESETn,
    input                        PREADY,
    input                        PSLVERR
);

    localparam [1:0] IDLE   = 2'b00,
                     SETUP  = 2'b01,
                     ACCESS = 2'b10;

    reg [1:0] ns, cs;

    // FSM Sequential Logic
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn)
            cs <= IDLE;
        else
            cs <= ns;
    end

    // FSM Next-State Logic
    always @(*) begin
        case (cs)
            IDLE:   ns = transfer ? SETUP : IDLE;
            SETUP:  ns = ACCESS; // SETUP lasts exactly 1 cycle
            ACCESS: begin
                if (PREADY && !transfer)
                    ns = IDLE;
                else if (PREADY && transfer)
                    ns = SETUP;
                else
                    ns = ACCESS;
            end
            default: ns = IDLE;
        endcase
    end

    // Combinational Output Decoding (Clean Latch-Free Design)
    always @(*) begin
        // Default assignments to prevent unintended latches
        PSEL    = 1'b0;
        PENABLE = 1'b0;
        PWRITE  = SWRITE;
        PADDR   = SADDR;
        PWDATA  = SWDATA;
        PSTRB   = SSTRB;
        PPROT   = SPROT;

        case (cs)
            IDLE: begin
                PSEL    = 1'b0;
                PENABLE = 1'b0;
                PENABLE = 1'b0;
            end
            SETUP: begin
                PSEL    = 1'b1;
                PENABLE = 1'b0;
            end
            ACCESS: begin
                PSEL    = 1'b1;
                PENABLE = 1'b1;
            end
            default: begin
                PSEL    = 1'b0;
                PENABLE = 1'b0;
            end
        endcase
    end

    // APB5 Wakeup Signaling
    always @(*) begin
        if (!PRESETn)
            PWAKEUP = 1'b0;
        else begin
            case (cs)
                IDLE:    PWAKEUP = transfer;
                SETUP:   PWAKEUP = 1'b1;
                ACCESS:  PWAKEUP = 1'b1;
                default: PWAKEUP = 1'b0;
            endcase
        end
    end

    // APB5 Parity Protection
    always @(*) begin
        if (!ENABLE_PARITY) begin
            PADDRPAR  = 1'b0;
            PWDATAPAR = 1'b0;
            PSTRBPAR  = 1'b0;
            PPROTPAR  = 1'b0;
        end else begin
            PADDRPAR  = ^PADDR;
            PWDATAPAR = ^PWDATA;
            PSTRBPAR  = ^PSTRB;
            PPROTPAR  = ^PPROT;
        end
    end

endmodule

