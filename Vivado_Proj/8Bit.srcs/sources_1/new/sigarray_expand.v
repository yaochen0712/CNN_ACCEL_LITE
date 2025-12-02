`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/11/03 13:51:26
// Design Name: 
// Module Name: sigarray_expand
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


module sigarray_expand
#(
    parameter IN_WIDTH = 8,
    parameter OUT_WIDTH = 16,
    parameter CHANNEL = 128
)
(
    input  wire [IN_WIDTH*CHANNEL-1:0] i_data_in,
    output wire [OUT_WIDTH*CHANNEL-1:0] o_data_out
    );
    genvar i;
    generate
        for (i = 0; i < CHANNEL; i = i + 1) begin : sig_expand_loop
            assign o_data_out[i*OUT_WIDTH +: OUT_WIDTH] = 
            {{(OUT_WIDTH - IN_WIDTH){i_data_in[i*IN_WIDTH + IN_WIDTH -1]}}, i_data_in[i*IN_WIDTH +: IN_WIDTH]};
        end
    endgenerate
endmodule
