`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// 一直循环提供命令给Controller
// 
//////////////////////////////////////////////////////////////////////////////////


module proj_programe(
    input clk,
    input rst_n,

    input i_command_ready,
    output o_command_valid,
    output [15:0] o_command_data
    );
    localparam PROG_LENGTH = 3;
    reg [16*4-1:0] command_memory
    = {
        16'b1_1010_1_0111_1001_00, //00_1_010_0111_1001_00
        16'b1_1000_1_0101_0111_01, //layer 1 start
        16'b1_1001_0_0001_0101_11  //layer 2 start
    };
    reg [4:0] prog_counter;
    reg command_valid_reg;
    assign o_command_valid = command_valid_reg;
    wire command_fire;
    assign command_fire = o_command_valid & i_command_ready;

    
endmodule
