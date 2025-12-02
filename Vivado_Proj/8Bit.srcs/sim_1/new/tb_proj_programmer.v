`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/11/24 16:03:33
// Design Name: 
// Module Name: tb_proj_programmer
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
`define CLK_PERIOD 10 

module tb_proj_programmer(

    );
    reg clk = 0;
    reg command_ready = 0;
    reg rst_n;
    wire [15:0] command_data;
    wire command_valid;

    
    proj_programe u_proj_programe(
        .clk             	(clk              ),
        .rst_n           	(rst_n            ),
        .i_command_ready 	(command_ready  ),
        .o_command_valid 	(command_valid  ),
        .o_command_data  	(command_data   )
    );
    
    
    always #(`CLK_PERIOD / 2 ) clk = ~clk;

    initial begin
        #2
        rst_n = 0;
        #(2*`CLK_PERIOD)
        rst_n = 1;
        #(`CLK_PERIOD)
        command_ready <= 1;
        #(`CLK_PERIOD * 20)
        command_ready <= 0;
        #(`CLK_PERIOD *4)
        command_ready <= 1;
        #(`CLK_PERIOD *15)
        $finish;
    end
endmodule
