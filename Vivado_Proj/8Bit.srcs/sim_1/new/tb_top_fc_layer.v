`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/11/18 15:31:09
// Design Name: 
// Module Name: tb_top_fc_layer
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


module tb_top_fc_layer(

    );

    reg clk,r_en,rst_n;
// output declaration of module BM_control_stream_v2
    localparam DW = 8;

    BM_control_stream_v2 #(
        .WIDTH        	(DW         ),
        .ADDR_RANGE   	(21504       )
    )
    u_DATA_IN_CTRL(
        .clk              	(clk               ),
        .rst_n            	(rst_n             ),
        .en               	(r_en                ),
        .o_addr_done      	(w_test_addr_done       ),
        .i_bram_data      	(w_test_bram_data       ),
        .o_bram_addr      	(w_test_bram_addr       ),
        .o_data_out       	(w_test_data        ),
        .o_data_out_valid 	(w_test_data_valid  ),
        .i_data_out_ready 	(w_test_data_ready  )
    );

    Data_buffer #(
        .DATA_WIDTH  	(DW           ),
        .BUFFER_DEPTH	(512        )
    )
    u_Data_Buffer(
        .clk         	(clk          ),
        .rst_n       	(rst_n        ),
        .i_fifo_data 	(w_test_data  ),
        .i_fifo_valid	(w_test_data_valid  ),
        .o_fifo_ready	(w_test_data_ready  ),
        .o_data_out  	(w_fifo_data            ),
        .o_data_valid	(w_fifo_data_valid            ),
        .i_data_ready	(w_fifo_data_ready        ),
        .i_ctrl_enable	(w_n_bram_setaddr_zero        )
    );


    //测试用的数据BRAM
    // output declaration of module simv_data_input
    
    simv_data_input u_simv_data_input(
        .clka  	(clk   ),
        .rsta  	(~rst_n   ),
        .wea   	(1'b0    ),
        .addra 	(w_test_bram_addr  ),
        .dina  	(8'h00   ),
        .douta 	(w_test_bram_data  )
    );
    
    //控制器例化
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
        .i_layer_error                   	(1'b0                     ),
        .o_layer_en                      	(w_layer_en                       ),
        .o_soc_error                     	(w_soc_error                      ),
        .i_command_valid                 	(w_command_valid                  ),
        .i_command_data                  	(w_command_data                   ),
        .o_command_ready                 	(w_command_ready                  ),
        .i_layer_done                    	(w_layer_done                     ),
        .o_dp_sel                        	(w_dp_sel                         ),
        .o_layer_idx                     	(w_layer_idx                      ),
        .o_accumulator_cfg_en            	(w_accumulator_cfg_en             ),
        .o_accumulator_cfg_channel_innum 	(w_accumulator_cfg_channel_innum  ),
        .o_accumulator_cfg_gate          	(w_accumulator_cfg_gate           ),
        .o_trunction_cfg_en              	(w_trunction_cfg_en               ),
        .o_trunction_cfg_lsb_idx         	(w_trunction_cfg_lsb_idx          ),
        .o_trunction_cfg_saturate_en     	(w_trunction_cfg_saturate_en      ),
        .o_relu_en                       	(w_relu_en                        ),
        .o_model_finished                	(o_model_finished                 ),
        .o_n_bram_setaddr_zero           	(w_n_bram_setaddr_zero            ),
        .i_out_cache_ready               	(w_out_cache_ready                ),
        .i_out_cache_valid               	(w_out_cache_valid                ),
        .o_out_mux_sel                   	(w_out_mux_sel                    )
    );
    
    //程序模块
    // output declaration of module proj_programe
    wire o_command_valid;
    wire [15:0] o_command_data;
    
    proj_programe u_proj_programe(
        .clk             	(clk              ),
        .rst_n           	(rst_n            ),
        .i_command_ready 	(w_command_ready  ),
        .o_command_valid 	(w_command_valid  ),
        .o_command_data  	(w_command_data   )
    );
    
    

    top_fc_module #(
        .MULTI_WIDTH          	(128                        ),
        .D_WIDTH              	(8                          ),
        .MAX_LAYER            	(4                          ),
        .INPUT_CHANNEL_MAXNUM 	(512                        ),
        .ACCUMULATOR_OUTWIDTH 	(24                         ),
        .MAX_OUTPUT_LAYER     	(128                        ),
        .GATE_PARA            	(6)
    )
    u_top_fc_module(
        .clk                            	(clk                             ),
        .rst_n                          	(rst_n                           ),
        .i_fifo_data                    	(w_fifo_data                     ),
        .i_fifo_valid                   	(w_fifo_data_valid         ),
        .o_fifo_ready                   	(w_fifo_data_ready         ),
        .i_ctrl_start                   	(w_layer_en                    ),
        .o_fc_error                     	(w_fc_error                      ),
        .o_fc_layerdone                 	(w_layer_done                  ),
        .i_dp_sel                       	(w_dp_sel                        ),
        .i_layer_index                  	(w_layer_index                   ),
        .i_accumulator_cfg_en           	(w_accumulator_cfg_en            ),
        .i_accumulator_cfg_channel_inum 	(w_accumulator_cfg_channel_inum  ),
        .i_accumulator_cfg_gate         	(w_accumulator_cfg_gate          ),
        .i_trunction_cfg_en             	(w_trunction_cfg_en              ),
        .i_trunction_cfg_lsb_index      	(w_trunction_cfg_lsb_index       ),
        .i_trunction_cfg_saturate_en    	(w_trunction_cfg_saturate_en     ),
        .i_relu_en                      	(w_relu_en                       ),
        .i_n_bram_setaddr_zero          	(w_n_bram_setaddr_zero           ),
        .i_out_mux_sel                  	(w_out_mux_sel                   ),
        .i_fc2cap_valid                 	(w_fc2cap_valid                  ),
        .o_fc2cap_ready                 	(w_fc2cap_ready                  ),
        .o_fc2cpa_data                  	(w_fc2cpa_data                   )
    );
    

endmodule


