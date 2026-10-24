`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09.09.2026 19:29:46
// Design Name: 
// Module Name: APB_Clockgate
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

module APB_Clockgate (
    input  CLK,
    input  EN,      // gate enable / wake request
    output GCLK
);
 
`ifdef XILINX_FPGA
 
    BUFGCE u_bufgce (
        .I  (CLK),
        .CE (EN),
        .O  (GCLK)
    );
 
`else
 
    reg en_latched;
 
    always @(*) begin
        if (!CLK)
            en_latched = EN;
    end
 
    assign GCLK = CLK & en_latched;
 
`endif
 
endmodule
 
