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
    reg [16*3-1:0] command_memory
    = {
        16'b1_1010_1_0111_1001_00, //00_1_010_0111_1001_00
        16'b1_1000_1_0101_0111_10, //layer 1 start
        16'b1_1001_0_0001_0101_11  //layer 2 start
        //16'b0_0000_0_0000_0000_01   //rest ram wait for the next layer
    };
    reg [4:0] prog_counter;
    reg command_valid_reg;
    assign o_command_valid = command_valid_reg;
    wire command_fire;
    assign command_fire = o_command_valid & i_command_ready;
    assign o_command_data = command_memory[(16 * prog_counter)+:16];

    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            prog_counter <= 0;
            command_valid_reg <= 0;
        end
        else begin
            if(command_fire)begin
                prog_counter <= prog_counter + 1;
                if(prog_counter == PROG_LENGTH-1)begin
                    prog_counter <= 0;
                end
            end
            command_valid_reg <= 1;
        end
    end
    
endmodule
