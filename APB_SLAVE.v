`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09.09.2026 18:14:39
// Design Name: 
// Module Name: APB_SLAVE
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

module APB_SLAVE #(
    parameter ADDR_WIDTH      = 64,
    parameter DATA_WIDTH      = 64,
    parameter MEM_WIDTH       = DATA_WIDTH,
    parameter MEM_DEPTH       = 2048,
    parameter ENABLE_PARITY   = 1,
    parameter NUM_WAIT_STATES = 0
) (
    input                        PSEL,
    input                        PENABLE,
    input                        PWRITE,
    input  [ADDR_WIDTH-1:0]      PADDR,
    input  [DATA_WIDTH-1:0]      PWDATA,
    input  [DATA_WIDTH/8-1:0]    PSTRB,
    input  [2:0]                 PPROT,

    input                        PWAKEUP,

    input                        PADDRPAR,
    input                        PWDATAPAR,
    input                        PSTRBPAR,
    input                        PPROTPAR,

    input                        PCLK,
    input                        PRESETn,

    output reg [DATA_WIDTH-1:0]  PRDATA,
    output                       PREADY,
    output reg                   PSLVERR,

    output reg                   PRDATAPAR,
    output reg                   PSLVERRPAR
);

    localparam STRB_WIDTH  = DATA_WIDTH/8;
    localparam INDEX_WIDTH = (MEM_DEPTH > 1) ? $clog2(MEM_DEPTH) : 1;

    // Word-aligned memory indexing
    wire [INDEX_WIDTH-1:0] mem_index = PADDR[INDEX_WIDTH+1:2];
    wire selected = PSEL && PWAKEUP;

    // ---------------------------------------------------------------
    // Configurable Wait States
    // ---------------------------------------------------------------
    reg [7:0] wait_cnt;

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn)
            wait_cnt <= 8'd0;
        else if (selected && PENABLE) begin
            if (wait_cnt == NUM_WAIT_STATES)
                wait_cnt <= 8'd0;
            else
                wait_cnt <= wait_cnt + 8'd1;
        end else begin
            wait_cnt <= 8'd0;
        end
    end

    assign PREADY = (selected && PENABLE && (wait_cnt == NUM_WAIT_STATES));

    // ---------------------------------------------------------------
    // Parity Verification
    // ---------------------------------------------------------------
    wire parity_ok = !ENABLE_PARITY ||
                      ((PADDRPAR  == ^PADDR)  &&
                       (PWDATAPAR == ^PWDATA) &&
                       (PSTRBPAR  == ^PSTRB)  &&
                       (PPROTPAR  == ^PPROT));

    // ---------------------------------------------------------------
    // BRAM-Inference Dedicated Memory Array & Internal Bus
    // ---------------------------------------------------------------
    (* ram_style = "block" *) reg [MEM_WIDTH-1:0] Cache [MEM_DEPTH-1:0];
    reg [DATA_WIDTH-1:0] ram_rdata;

    // Dedicated Write Port (Byte-Enable Array Write Pattern)
    integer i;
    always @(posedge PCLK) begin
        if (selected && PENABLE && PWRITE && parity_ok && (wait_cnt == NUM_WAIT_STATES)) begin
            for (i = 0; i < STRB_WIDTH; i = i + 1) begin
                if (PSTRB[i]) begin
                    Cache[mem_index][(i*8) +: 8] <= PWDATA[(i*8) +: 8];
                end
            end
        end
    end

    // Dedicated Read Port
    always @(posedge PCLK) begin
        if (selected && !PWRITE) begin
            ram_rdata <= Cache[mem_index];
        end
    end

    // ---------------------------------------------------------------
    // APB Response & Parity Generation
    // ---------------------------------------------------------------
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            PSLVERR    <= 1'b0;
            PRDATA     <= {DATA_WIDTH{1'b0}};
            PRDATAPAR  <= 1'b0;
            PSLVERRPAR <= 1'b0;
        end else if (selected && PENABLE && (wait_cnt == NUM_WAIT_STATES)) begin
            if (!parity_ok) begin
                PSLVERR    <= 1'b1;
                PSLVERRPAR <= 1'b1;
            end else if (PWRITE) begin
                PSLVERR    <= 1'b0;
                PSLVERRPAR <= 1'b0;
            end else begin
                if (PSTRB != {STRB_WIDTH{1'b0}}) begin
                    PSLVERR    <= 1'b1;   // PSTRB must be zero during a read operation
                    PSLVERRPAR <= 1'b1;
                end else begin
                    PRDATA     <= ram_rdata;
                    PRDATAPAR  <= ^ram_rdata;
                    PSLVERR    <= 1'b0;
                    PSLVERRPAR <= 1'b0;
                end
            end
        end
    end

endmodule
