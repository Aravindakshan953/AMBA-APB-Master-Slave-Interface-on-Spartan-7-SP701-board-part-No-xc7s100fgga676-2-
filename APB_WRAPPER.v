`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09.09.2026 18:18:49
// Design Name: 
// Module Name: APB_WRAPPER
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

// =============================================================================
// APB_Wrapper.v
// Top-level integration of the APB5 Requester (Master) and Completer
// (Slave). Adds one genuinely novel, synthesizable power optimization on
// top of the protocol-level APB5 features: the Slave's clock is gated by
// PWAKEUP so its register bank stops toggling entirely whenever the bus
// is idle, instead of only clock-enabling the data path. This directly
// targets dynamic power, which scales with clock-net switching activity.
//
// A handful of internal signals (PSEL/PENABLE/PWRITE/PADDR/PWDATA/PSTRB/
// PREADY) are also exposed as *_MON monitor outputs purely for testbench
// observability -- they carry no functional meaning to a real system
// integrator and can be left unconnected.
// =============================================================================

module APB_WRAPPER #(
    parameter ADDR_WIDTH      = 64,
    parameter DATA_WIDTH      = 64,
    parameter MEM_DEPTH       = 2048,
    parameter ENABLE_PARITY   = 1,
    parameter NUM_WAIT_STATES = 0
) (
    input                       PCLK,
    input                       PRESETn,

    input                       SWRITE,
    input  [ADDR_WIDTH-1:0]     SADDR,
    input  [DATA_WIDTH-1:0]     SWDATA,
    input  [DATA_WIDTH/8-1:0]   SSTRB,
    input  [2:0]                SPROT,
    input                       transfer,

    output [DATA_WIDTH-1:0]     PRDATA,
    output                      PSLVERR,
    output                      PWAKEUP,

    // ---- verification-only monitor ports (safe to leave unconnected) ----
    output                      PSEL_MON,
    output                      PENABLE_MON,
    output                      PREADY_MON
);

    wire                     PSEL, PENABLE, PWRITE;
    wire [ADDR_WIDTH-1:0]    PADDR;
    wire [DATA_WIDTH-1:0]    PWDATA;
    wire [DATA_WIDTH/8-1:0]  PSTRB;
    wire [2:0]               PPROT;
    wire                     PREADY;

    wire PADDRPAR, PWDATAPAR, PSTRBPAR, PPROTPAR;
    wire PRDATAPAR, PSLVERRPAR;

    assign PSEL_MON    = PSEL;
    assign PENABLE_MON = PENABLE;
    assign PREADY_MON  = PREADY;

    // -----------------------------------------------------------------
    // Single, explicit global clock buffer on the raw PCLK pin.
    //
    // Why this exists: the Slave's clock gate below is itself a second
    // global buffer (BUFGCE). If BOTH that buffer and the design's main
    // clock net try to attach directly to the PCLK IOB independently,
    // Vivado's placer has to fit two separate IOB->BUFG dedicated routes
    // from the same pin, which on 7-series parts fails the
    // rule_gclkio_bufg DRC ("An IOB driving a BUFG must use a CCIO in the
    // same half side of chip as the BUFG") whenever the two buffers don't
    // land on compatible BUFGCTRL sites -- exactly the
    // "[Place 30-574]... Placer failed" error this fixes.
    //
    // The correct, Xilinx-documented pattern (UG472) is to cascade: only
    // ONE buffer (this BUFG) connects to the IOB via dedicated route, and
    // every other clock buffer in the design -- including the Slave's
    // BUFGCE -- is sourced from this buffer's output over normal global
    // clock routing instead of from the pin directly.
    // -----------------------------------------------------------------
`ifdef XILINX_FPGA
    wire pclk_g;
    BUFG u_sysclk_bufg (
        .I (PCLK),
        .O (pclk_g)
    );
`else
    // Icarus/generic simulation: BUFG is a Xilinx primitive with no open
    // model, so just pass the clock through untouched.
    wire pclk_g = PCLK;
`endif

    // -----------------------------------------------------------------
    // Dynamic-power reduction: gate the Slave's clock off PWAKEUP.
    //
    // The enable is REGISTERED before it reaches the clock-gate cell
    // (UG472-style guidance for BUFGCE.CE, and standard ASIC ICG
    // practice): a combinational CE net driven straight from PWAKEUP
    // would fail Xilinx's clock-tree DRCs and risks a glitchy enable.
    // Because PWAKEUP is already asserted one cycle ahead of SETUP, this
    // extra register stage lines up exactly -- slave_clk_en becomes 1 on
    // the very cycle the Master enters SETUP, so the Slave's clock is
    // already running by the time it matters, with zero performance
    // penalty.
    //
    // The register is asynchronously forced to 1 on reset (rather than
    // gated off), so the Slave's own synchronous reset logic still gets
    // clock edges to reset on even if the bus is otherwise idle/asleep.
    // -----------------------------------------------------------------
    reg slave_clk_en;
    always @(posedge pclk_g or negedge PRESETn) begin
        if (~PRESETn)
            slave_clk_en <= 1'b1;
        else
            slave_clk_en <= PWAKEUP;
    end

    wire SCLK;

    // Cascaded from pclk_g (global routing), NOT from the raw PCLK pin --
    // see the comment above.
    APB_Clockgate u_slave_clkgate (
        .CLK  (pclk_g),
        .EN   (slave_clk_en),
        .GCLK (SCLK)
    );

    // -----------------------------------------------------------------
    // Requester (Master) -- runs on the same buffered clock
    // -----------------------------------------------------------------
    APB_MASTER #(
        .ADDR_WIDTH    (ADDR_WIDTH),
        .DATA_WIDTH    (DATA_WIDTH),
        .ENABLE_PARITY (ENABLE_PARITY)
    ) Master (
        .PCLK      (pclk_g),
        .PRESETn   (PRESETn),
        .SWRITE    (SWRITE),
        .SADDR     (SADDR),
        .SWDATA    (SWDATA),
        .SSTRB     (SSTRB),
        .SPROT     (SPROT),
        .transfer  (transfer),

        .PSEL      (PSEL),
        .PENABLE   (PENABLE),
        .PWRITE    (PWRITE),
        .PADDR     (PADDR),
        .PWDATA    (PWDATA),
        .PSTRB     (PSTRB),
        .PPROT     (PPROT),

        .PWAKEUP   (PWAKEUP),

        .PADDRPAR  (PADDRPAR),
        .PWDATAPAR (PWDATAPAR),
        .PSTRBPAR  (PSTRBPAR),
        .PPROTPAR  (PPROTPAR),

        .PREADY    (PREADY),
        .PSLVERR   (PSLVERR)
    );

    // -----------------------------------------------------------------
    // Completer (Slave) -- runs on the PWAKEUP-gated clock
    // -----------------------------------------------------------------
    APB_SLAVE #(
        .ADDR_WIDTH      (ADDR_WIDTH),
        .DATA_WIDTH      (DATA_WIDTH),
        .MEM_DEPTH       (MEM_DEPTH),
        .ENABLE_PARITY   (ENABLE_PARITY),
        .NUM_WAIT_STATES (NUM_WAIT_STATES)
    ) Slave (
        .PCLK       (SCLK),
        .PRESETn    (PRESETn),

        .PSEL       (PSEL),
        .PENABLE    (PENABLE),
        .PWRITE     (PWRITE),
        .PADDR      (PADDR),
        .PWDATA     (PWDATA),
        .PSTRB      (PSTRB),
        .PPROT      (PPROT),

        .PWAKEUP    (PWAKEUP),

        .PADDRPAR   (PADDRPAR),
        .PWDATAPAR  (PWDATAPAR),
        .PSTRBPAR   (PSTRBPAR),
        .PPROTPAR   (PPROTPAR),

        .PRDATA     (PRDATA),
        .PREADY     (PREADY),
        .PSLVERR    (PSLVERR),

        .PRDATAPAR  (PRDATAPAR),
        .PSLVERRPAR (PSLVERRPAR)
    );

endmodule
