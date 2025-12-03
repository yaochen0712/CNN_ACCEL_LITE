`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/11/24 16:15:20
// Design Name: 
// Module Name: tb_ctrl_top
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

module tb_ctrl_top(

    );

    reg clk = 0;
    wire command_ready;
    reg rst_n;
    wire [15:0] command_data;
    wire command_valid;
    reg layer_done = 0;

    proj_programe u_proj_programe(
        .clk             	(clk              ),
        .rst_n           	(rst_n            ),
        .i_command_ready 	(command_ready  ),
        .o_command_valid 	(command_valid  ),
        .o_command_data  	(command_data   )
    );
    
    // output declaration of module Control
    wire o_layer_en;
    wire o_soc_error;
    wire o_dp_sel;
    wire [$clog2(8)-1:0] o_layer_idx;
    wire o_accumulator_cfg_en;
    wire [$clog2(512)-1:0] o_accumulator_cfg_channel_innum;
    wire [$clog2(6):0] o_accumulator_cfg_gate;
    wire o_trunction_cfg_en;
    wire [$clog2(24-8)-1:0] o_trunction_cfg_lsb_idx;
    wire o_trunction_cfg_saturate_en;
    wire o_relu_en;
    wire o_n_bram_setaddr_zero;
    wire model_finish;

    Control #(
        .MAX_LAYER            	(8    ),
        .INPUT_CHANNEL_MAXNUM 	(512  ),
        .ACCUMULATOR_OUTWIDTH 	(24   ),
        .MAX_OUTPUT_LAYER     	(128  ),
        .GATE_MIN_SCALE_COEF  	(6    ),
        .D_WIDTH              	(8    ))
    u_Control(
        .clk                             	(clk                              ),
        .rst_n                           	(rst_n                            ),
        .i_layer_error                   	(1'b0                    ),
        .o_layer_en                      	(o_layer_en                       ),
        .o_soc_error                     	(o_soc_error                      ),
        .i_command_valid                 	(command_valid                  ),
        .i_command_data                  	(command_data                   ),
        .o_command_ready                 	(command_ready                  ),
        .i_layer_done                    	(layer_done                     ),
        .o_dp_sel                        	(o_dp_sel                         ),
        .o_layer_idx                     	(o_layer_idx                      ),
        .o_accumulator_cfg_en            	(o_accumulator_cfg_en             ),
        .o_accumulator_cfg_channel_innum 	(o_accumulator_cfg_channel_innum  ),
        .o_accumulator_cfg_gate          	(o_accumulator_cfg_gate           ),
        .o_trunction_cfg_en              	(o_trunction_cfg_en               ),
        .o_trunction_cfg_lsb_idx         	(o_trunction_cfg_lsb_idx          ),
        .o_trunction_cfg_saturate_en     	(o_trunction_cfg_saturate_en      ),
        .o_relu_en                       	(o_relu_en                        ),
        .o_model_finished                   (model_finish                   ),
        .o_n_bram_setaddr_zero           	(o_n_bram_setaddr_zero            ),
        .i_out_cache_ready                  (1'b1),
        .i_out_cache_valid                  (1'b1),
        .o_out_mux_sel                      (w_out_mux_sel)
    );
    
    
    always #(`CLK_PERIOD / 2 ) clk = ~clk;

    initial begin
        #(10 * `CLK_PERIOD)
        forever begin
        layer_done = 0;
        #((128 + 12) * `CLK_PERIOD)   layer_done = 1;
        #(4 * `CLK_PERIOD)  layer_done = 0;
        #((32 + 12) * `CLK_PERIOD)   layer_done = 1;
        #(4 * `CLK_PERIOD)  layer_done = 0;
        #((2 + 12) * `CLK_PERIOD) layer_done = 1;
        #(4 * `CLK_PERIOD)  layer_done = 0;
        end
    end
    initial begin
        #2
        rst_n = 0;
        #(2*`CLK_PERIOD)
        rst_n = 1;
        #(`CLK_PERIOD * 1024)
        
        $finish;
    end
endmodule
