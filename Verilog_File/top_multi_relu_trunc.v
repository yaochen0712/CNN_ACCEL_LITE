`timescale 1ns / 1ps
//封装多通道的ReLu和Trunc模块
//因为

module top_multi_relu_trunc#(
    parameter CHANNEL = 128,
    parameter D_IWIDTH = 24,
    parameter D_OWIDTH = 8
)
(
    input clk,
    input rst_n,
    input [D_IWIDTH*CHANNEL-1:0] i_data_in, 
    input i_data_in_valid,
    output o_data_in_ready,    
    output [D_OWIDTH*CHANNEL-1:0] o_data_out,
    output o_data_out_valid,
    input i_data_out_ready,

    //接口配置
    input i_cfg_en,
    input [$clog2(D_IWIDTH-D_OWIDTH)-1:0] i_trunction_cfg_lsb_index,
    input i_trunction_cfg_saturate_en,
    input i_relu_en
);
    wire [D_OWIDTH*CHANNEL-1:0] w_trunc_relu_data;
    wire [CHANNEL-1:0] w_trunc_relu_valid;
    wire [CHANNEL-1:0] w_trunc_relu_ready;
    wire [CHANNEL-1:0] w_trunc_ready;
    wire [CHANNEL-1:0] w_relu_valid;
    assign o_data_out_valid = &w_relu_valid;
    assign o_data_in_ready = &w_trunc_ready;
    genvar i;
    generate
        for(i=0;i<CHANNEL;i=i+1)begin :GEN_RELU_TRUNC
            
            trunction #(
                .DIN_WIDTH  	(D_IWIDTH  ),
                .DOUT_WIDTH 	(D_OWIDTH   )
            )
            u_trunction(
                .clk                         	(clk                          ),
                .rst_n                       	(rst_n                        ),
                .i_din                       	(i_data_in[ (i+1)*D_IWIDTH-1 : i*D_IWIDTH ]                        ),
                .i_din_valid                 	(i_data_in_valid                  ),
                .o_din_ready                 	(w_trunc_ready[i]                  ),
                .o_dout                      	(w_trunc_relu_data[ (i+1)*D_OWIDTH-1 : i*D_OWIDTH ]                       ),
                .o_dout_valid                	(w_trunc_relu_valid[i]                 ),
                .i_dout_ready                	(w_trunc_relu_ready[i]                 ),
                .i_trunction_cfg_lsb_idx     	(i_trunction_cfg_lsb_index      ),
                .i_trunction_cfg_saturate_en 	(i_trunction_cfg_saturate_en  ),
                .i_trunction_cfg_en          	(i_cfg_en           )
            );
            
            
            ReLU #(
                .DATA_WIDTH 	(D_OWIDTH      )
            )
            u_ReLU(
                .clk              	(clk               ),
                .rst_n            	(rst_n             ),
                .i_data_in        	(w_trunc_relu_data[ (i+1)*D_OWIDTH-1 : i*D_OWIDTH ]         ),
                .i_data_in_valid  	(w_trunc_relu_valid[i]   ),
                .i_data_in_ready  	(w_trunc_relu_ready[i]   ),
                .o_data_out       	(o_data_out[ (i+1)*D_OWIDTH-1 : i*D_OWIDTH ]        ),
                .o_data_out_valid 	(w_relu_valid[i]  ),
                .o_data_out_ready 	(i_data_out_ready  ),
                .i_cfg_en         	(i_cfg_en          ),
                .i_relu_cfg       	(i_relu_en        )
            );
            
        end
    endgenerate

endmodule
