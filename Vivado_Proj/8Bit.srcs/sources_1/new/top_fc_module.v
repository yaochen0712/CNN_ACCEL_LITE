`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/11/17 01:14:19
// Design Name: 
// Module Name: top_fc_module
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


module top_fc_module
#(
    parameter MULTI_WIDTH = 128,
    parameter D_WIDTH = 8,
    parameter MAX_LAYER = 4,
    parameter INPUT_CHANNEL_MAXNUM = 512,
    parameter ACCUMULATOR_OUTWIDTH = 24,
    parameter MAX_OUTPUT_LAYER = 128,
    parameter GATE_PARA = 6//2-4-6......128的控制
)
(
    input clk,
    input rst_n,

    //FIFO接口
    input [D_WIDTH-1:0] i_fifo_data,
    input i_fifo_valid,
    output o_fifo_ready,

    //Controller接口
    input i_ctrl_start,
    output o_fc_error,
    output o_fc_layerdone,
    input i_dp_sel,
    input [$clog2(MAX_LAYER)-1:0] i_layer_index, //用于片选WEIGHT/索引BIAS
    input i_accumulator_cfg_en,
    input [$clog2(INPUT_CHANNEL_MAXNUM)-1:0] i_accumulator_cfg_channel_inum,//累加器需要加多少次 对应多少个输入通道
    input [$clog2(GATE_PARA):0] i_accumulator_cfg_gate,//门控，同时控制输出的数量
    input i_trunction_cfg_en,
    input [$clog2(ACCUMULATOR_OUTWIDTH-D_WIDTH):0] i_trunction_cfg_lsb_index,
    input i_trunction_cfg_saturate_en,
    input i_relu_en,
    input i_n_bram_setaddr_zero, //用于把控制器重置为0开始 方便下一次计算 正常使用的时候拉高 实现方法是和rst_n做and

    //Capture送给AXI_DMA的接口与MUX控制
    input i_out_mux_sel,
    output o_fc2cap_valid,
    input i_fc2cap_ready,
    output [D_WIDTH-1:0]o_fc2cpa_data
    );

    //这里是权重模块和片选择
    
    localparam WEIGHT_LAYER1_DWIDTH = 128*8;
    localparam DEPTH_LAYER1 = 512;
    localparam WEIGHT_LAYER2_DWIDTH = 32*8;
    localparam DEPTH_LAYER2 = 128;
    localparam WEIGHT_LAYER3_DWIDTH = 2*8;
    localparam DEPTH_LAYER3 = 32;

    localparam WEIGHT_BUS_DWIDTH = WEIGHT_LAYER1_DWIDTH;
    //由于是3层就要用的3个BUSMUX分成两层进行选择
    wire [WEIGHT_BUS_DWIDTH-1:0] w_l1mux_multi_data;
    wire w_l1mux_multi_valid;
    wire w_l1mux_multi_ready;
    wire [WEIGHT_BUS_DWIDTH-1:0] w_l21mux_l1mux_data,w_l22mux_l1mux_data;
    wire w_l21mux_l1mux_valid,w_l22mux_l1mux_valid;
    wire w_l21mux_l1mux_ready,w_l22mux_l1mux_ready;

    wire [WEIGHT_LAYER1_DWIDTH-1:0] w_weight_l1_data;
    wire w_weight_l1_valid;
    wire w_weight_l1_ready;
    wire [WEIGHT_LAYER2_DWIDTH-1:0] w_weight_l2_data;
    wire w_weight_l2_valid;
    wire w_weight_l2_ready;
    wire [WEIGHT_LAYER3_DWIDTH-1:0] w_weight_l3_data;
    wire w_weight_l3_valid;
    wire w_weight_l3_ready;

    BUS_MUX_B #(
        .D_WIDTH(WEIGHT_BUS_DWIDTH)
    ) 
    u_WEIGHT_L1_BUS_MUX_0
    (
        .data_a    	(w_l1mux_multi_data     ),
        .valid_a   	(w_l1mux_multi_valid    ),
        .ready_a   	(w_l1mux_multi_ready    ),
        .data_b_0  	(w_l21mux_l1mux_data   ),
        .valid_b_0 	(w_l21mux_l1mux_valid  ),
        .ready_b_0 	(w_l21mux_l1mux_ready  ),
        .data_b_1  	(w_l22mux_l1mux_data   ),
        .valid_b_1 	(w_l22mux_l1mux_valid  ),
        .ready_b_1 	(w_l22mux_l1mux_ready  ),
        .sel       	(i_layer_index[1]        )
    );
    
    BUS_MUX_B #(
        .D_WIDTH 	(WEIGHT_BUS_DWIDTH  )
    )
    u_WEIGHT_L2_BUS_MUX_0
    (
        .data_a    	(w_l21mux_l1mux_data    ),
        .valid_a   	(w_l21mux_l1mux_valid   ),
        .ready_a   	(w_l21mux_l1mux_ready   ),
        .data_b_0  	(w_weight_l1_data   ),
        .valid_b_0 	(w_weight_l1_valid  ),
        .ready_b_0 	(w_weight_l1_ready  ),
        .data_b_1  	({{(WEIGHT_LAYER1_DWIDTH-WEIGHT_LAYER2_DWIDTH){1'b0}},w_weight_l2_data}   ),
        .valid_b_1 	(w_weight_l2_valid  ),
        .ready_b_1 	(w_weight_l2_ready  ),
        .sel       	(i_layer_index[0]       )
    );
    
    BUS_MUX_B #(
        .D_WIDTH 	(WEIGHT_BUS_DWIDTH  )
    )
    u_WEIGHT_L2_BUS_MUX_1
    (
        .data_a    	(w_l22mux_l1mux_data     ),
        .valid_a   	(w_l22mux_l1mux_valid    ),
        .ready_a   	(w_l22mux_l1mux_ready    ),
        .data_b_0  	({{(WEIGHT_LAYER1_DWIDTH-WEIGHT_LAYER3_DWIDTH){1'b0}},w_weight_l3_data}   ),
        .valid_b_0 	(w_weight_l3_valid  ),
        .ready_b_0 	(w_weight_l3_ready  ),
        .data_b_1  	({WEIGHT_BUS_DWIDTH{1'b0}}   ),
        .valid_b_1 	(1'b0  ),
        .ready_b_1 	( ),
        .sel       	(i_layer_index[0]        )
    );
    
    //这些wire信号是给BRAM的接口信号
    wire [WEIGHT_LAYER1_DWIDTH-1:0] w_l1_weight_brctrl_data;
    wire [$clog2(DEPTH_LAYER1)-1:0] w_l1_weight_brctrl_addr;
    // wire w_l1_weight_brctrl_en;
    wire w_l1_bram_done;
    BM_control_stream_v2_V #(
        .WIDTH    (WEIGHT_LAYER1_DWIDTH),
        .ADDR_RANGE    (DEPTH_LAYER1)
    )
    u_BM_CTRL_L1_WEIGHT
    (
        .clk(clk),
        .rst_n((rst_n & i_n_bram_setaddr_zero)),
        .en(i_ctrl_start),
        .o_addr_done(w_l1_bram_done),
        .i_bram_data(w_l1_weight_brctrl_data),
        .o_bram_addr(w_l1_weight_brctrl_addr),
        .o_data_out(w_weight_l1_data),
        .o_data_out_valid(w_weight_l1_valid),
        .i_data_out_ready(w_weight_l1_ready)
    );
    l1_weight u_bram_l1_weight
    (
        .clka(clk), // input clka
        .rsta(~rst_n), // input rsta
        .wea(1'b0), // input [0 : 0] wea
        .addra(w_l1_weight_brctrl_addr), // input [8 : 0] addra
        .dina({WEIGHT_LAYER1_DWIDTH{1'b0}}), // input [127 : 0] dina
        .douta(w_l1_weight_brctrl_data) // output [127 : 0] douta
    );


    //这些wire信号是给BRAM的接口信号
    wire [WEIGHT_LAYER2_DWIDTH-1:0] w_l2_weight_brctrl_data;
    wire [$clog2(DEPTH_LAYER2)-1:0] w_l2_weight_brctrl_addr;
    // wire w_l2_weight_brctrl_en;
    wire w_l2_bram_done;
    BM_control_stream_v2_V #(
        .WIDTH    (WEIGHT_LAYER2_DWIDTH),
        .ADDR_RANGE    (DEPTH_LAYER2)
    )
    u_BM_CTRL_L2_WEIGHT
    (
        .clk(clk),
        .rst_n((rst_n & i_n_bram_setaddr_zero)),
        .en(i_ctrl_start),
        .o_addr_done(w_l2_bram_done),
        .i_bram_data(w_l2_weight_brctrl_data),
        .o_bram_addr(w_l2_weight_brctrl_addr),
        .o_data_out(w_weight_l2_data),
        .o_data_out_valid(w_weight_l2_valid),
        .i_data_out_ready(w_weight_l2_ready)
    );
    l2_weight u_bram_l2_weight
    (
        .clka(clk), // input clka
        .rsta(~rst_n), // input rsta
        .wea(1'b0), // input [0 : 0] wea
        .addra(w_l2_weight_brctrl_addr), // input [6 : 0] addra
        .dina({WEIGHT_LAYER2_DWIDTH{1'b0}}), // input [255 : 0] dina
        .douta(w_l2_weight_brctrl_data) // output [255 : 0] douta
    );

    //这些wire信号是给BRAM的接口信号
    wire [WEIGHT_LAYER3_DWIDTH-1:0] w_l3_weight_brctrl_data;
    wire [$clog2(DEPTH_LAYER3)-1:0] w_l3_weight_brctrl_addr;
    // wire w_l3_weight_brctrl_en;
    wire w_l3_bram_done;
    BM_control_stream_v2_V #(
        .WIDTH    (WEIGHT_LAYER3_DWIDTH),
        .ADDR_RANGE    (DEPTH_LAYER3)
    )
    u_BM_CTRL_L3_WEIGHT
    (
        .clk(clk),
        .rst_n((rst_n & i_n_bram_setaddr_zero)),
        .en(i_ctrl_start),
        .o_addr_done(w_l3_bram_done), 
        .i_bram_data(w_l3_weight_brctrl_data),
        .o_bram_addr(w_l3_weight_brctrl_addr),
        .o_data_out(w_weight_l3_data),
        .o_data_out_valid(w_weight_l3_valid),
        .i_data_out_ready(w_weight_l3_ready)
    );
    l3_weight u_bram_l3_weight
    (
        .clka(clk), // input clka
        .rsta(~rst_n), // input rsta
        .wea(1'b0), // input [0 : 0] wea
        .addra(w_l3_weight_brctrl_addr), // input [4 : 0] addra
        .dina({WEIGHT_LAYER3_DWIDTH{1'b0}}), // input [15 : 0] dina
        .douta(w_l3_weight_brctrl_data) // output [15 : 0] douta
    );
    //todo:把BRAM的数据顺序确定好后直接例化连接

    //DP-MUX
    wire [D_WIDTH-1:0] w_dpmux_cache_data;
    wire w_dpmux_cache_valid;
    wire w_dpmux_cache_ready;
    wire [D_WIDTH-1:0] w_dpmux_multi_data;
    wire w_dpmux_multi_valid;
    wire w_dpmux_multi_ready;
    
    BUS_MUX_B #(
        .D_WIDTH 	(D_WIDTH  ))
    u_BUS_MUX(
        .data_a    	(w_dpmux_multi_data    ),
        .valid_a   	(w_dpmux_multi_valid    ),
        .ready_a   	(w_dpmux_multi_ready    ),
        .data_b_0  	(w_dpmux_cache_data   ),
        .valid_b_0 	(w_dpmux_cache_valid  ),
        .ready_b_0 	(w_dpmux_cache_ready  ),
        .data_b_1  	(i_fifo_data   ),
        .valid_b_1 	(i_fifo_valid  ),
        .ready_b_1 	(o_fifo_ready ),
        .sel       	(i_dp_sel        )
    );
    
    //乘法器模块例化
    wire [D_WIDTH*MULTI_WIDTH-1:0] w_multi_data;
    assign w_multi_data = {MULTI_WIDTH{w_dpmux_multi_data}};
    wire w_multi_error;
    wire [2*D_WIDTH*MULTI_WIDTH-1:0] w_multi_accum_data;
    wire w_multi_accum_valid;
    wire w_multi_accum_ready;

    multi_array #(
        .NUM_MULTS  	(MULTI_WIDTH   ),        
        .DIN_WIDTH  	(D_WIDTH       ),      
        .WGT_WIDTH  	(D_WIDTH       ),
        .DOUT_WIDTH 	(16            ),
        .LATENCY    	(3             ),
        .GATE_PARA  	(GATE_PARA     )
    )
    u_multi_array(
        .clk                 	(clk                  ),
        .rst_n               	(rst_n                ),
        .o_error             	(w_multi_error        ),
        .i_bram_data_din     	(w_multi_data      ),
        .i_bram_data_valid   	(w_dpmux_multi_valid    ),
        .o_bram_data_ready   	(w_dpmux_multi_ready    ),
        .i_bram_weight_din   	(w_l1mux_multi_data    ),
        .i_bram_weight_valid 	(w_l1mux_multi_valid  ),
        .o_bram_weight_ready 	(w_l1mux_multi_ready  ),
        .o_data_out          	(w_multi_accum_data           ),
        .o_data_out_valid    	(w_multi_accum_valid     ),
        .i_data_out_ready    	(w_multi_accum_ready     ),
        .i_cfg_valid         	(i_accumulator_cfg_en          ),
        .i_gate_en           	(i_accumulator_cfg_gate            )
    );
    

    //BIAS的内存控制器
    wire [D_WIDTH*MAX_OUTPUT_LAYER-1:0] w_bias_bram_bmctrl_data;
    wire [$clog2(MAX_LAYER)-1:0] w_bias_bram_bmctrl_addr;
    wire [D_WIDTH*MAX_OUTPUT_LAYER-1:0] w_bmctrl_accum_data;
    wire w_bmctrl_accum_valid;
    wire w_bmctrl_accum_ready;
    wire w_bias_bram_done;

    BM_control_stream_v2_V #(
        .WIDTH        	(D_WIDTH*MAX_OUTPUT_LAYER         ),
        .ADDR_RANGE   	(MAX_LAYER       )
        )
    u_BM_BIAS_CTRL(
        .clk              	(clk               ),
        .rst_n            	((rst_n & i_n_bram_setaddr_zero)             ),
        .en               	(i_ctrl_start                ),
        .o_addr_done      	(w_bias_bram_done       ),
        .i_bram_data      	(w_bias_bram_bmctrl_data       ),
        .o_bram_addr      	(w_bias_bram_bmctrl_addr       ),
        .o_data_out       	(w_bmctrl_accum_data        ),
        .o_data_out_valid 	(w_bmctrl_accum_valid  ),
        .i_data_out_ready 	(w_bmctrl_accum_ready  )
    );
    bias_mem u_bias_mem
    (
        .clka(clk), // input clka
        .rsta(~rst_n), // input rsta
        .wea(1'b0), // input [0 : 0] wea
        .addra(w_bias_bram_bmctrl_addr), // input [1 : 0] addra
        .dina({D_WIDTH*MAX_OUTPUT_LAYER{1'b0}}), // input [1023 : 0] dina
        .douta(w_bias_bram_bmctrl_data) // output [1023 : 0] douta
    );

    wire [ACCUMULATOR_OUTWIDTH*MULTI_WIDTH-1:0] w_accum_trunc_data;
    wire w_accum_trunc_valid;
    wire w_accum_trunc_ready;
    Accumulator #(
        .D_WIDTH           	(ACCUMULATOR_OUTWIDTH   ),
        .COUNT_WIDTH       	($clog2(512)    ),
        .GATE_PARA         	(GATE_PARA    ),
        .CHANNEL_NUM       	(MAX_OUTPUT_LAYER  ),
        .MULTIOUT_DWIDTH   	(D_WIDTH * 2   ),
        .CHANNEL_DATAWIDTH 	(D_WIDTH    )
    )
    u_Accumulator(
        .clk                  	(clk                   ),
        .rst_n                	(rst_n                 ),
        .i_count_limit        	(i_accumulator_cfg_channel_inum         ),
        .i_cfg_gate_en        	(i_accumulator_cfg_gate         ),
        .i_accumulator_cfg_en 	(i_accumulator_cfg_en  ),
        .i_data_in            	(w_multi_accum_data             ),
        .i_data_in_valid      	(w_multi_accum_valid       ),
        .o_data_in_ready      	(w_multi_accum_ready       ),
        .i_bias_in            	(w_bmctrl_accum_data             ),
        .i_bias_in_valid      	(w_bmctrl_accum_valid       ),
        .o_bias_in_ready      	(w_bmctrl_accum_ready       ),
        .o_data_out           	(w_accum_trunc_data            ),
        .o_data_out_valid     	(w_accum_trunc_valid      ),
        .i_data_out_ready     	(w_accum_trunc_ready      )
    );

    //ReLu和Trunc模块
    wire [D_WIDTH*MULTI_WIDTH-1:0] w_trunc_cache_data;
    wire w_trunc_cache_valid;
    wire w_trunc_cache_ready;
    
    top_multi_relu_trunc #(
        .CHANNEL  	(MULTI_WIDTH  ),
        .D_IWIDTH 	(ACCUMULATOR_OUTWIDTH   ),
        .D_OWIDTH 	(D_WIDTH    )
    )
    u_top_multi_relu_trunc(
        .clk                         	(clk                          ),
        .rst_n                       	(rst_n                        ),
        .i_data_in                   	(w_accum_trunc_data               ),
        .i_data_in_valid             	(w_accum_trunc_valid              ),
        .o_data_in_ready             	(w_accum_trunc_ready              ),
        .o_data_out                  	(w_trunc_cache_data               ),
        .o_data_out_valid            	(w_trunc_cache_valid             ),
        .i_data_out_ready            	(w_trunc_cache_ready             ),
        .i_cfg_en                    	(i_trunction_cfg_en              ),
        .i_trunction_cfg_lsb_index   	(i_trunction_cfg_lsb_index    ),
        .i_trunction_cfg_saturate_en 	(i_trunction_cfg_saturate_en  ),
        .i_relu_en                   	(i_relu_en                    )
    );
    
    //Cache模块
    // output declaration of module Cache


    //给到Capture送出到PS的接口
    wire [D_WIDTH-1:0] w_outmux_cache_data;
    wire w_outmux_cache_valid;
    wire w_outmux_cache_ready;

    wire o_mem_full;
    wire o_mem_empty;

    Cache #(
        .D_WIDTH   	(D_WIDTH                 ),
        .CHANNEL   	(MULTI_WIDTH              ),
        .GATE_PARA 	(GATE_PARA )
        )
    u_Cache(
        .clk                   	(clk                    ),
        .rst_n                 	(rst_n                  ),
        .i_cfg_gate_en         	(i_accumulator_cfg_gate          ),
        .i_cfg_valid           	(i_trunction_cfg_en            ),
        .i_data_parallel       	(w_trunc_cache_data        ),
        .i_data_parallel_valid 	(w_trunc_cache_valid  ),
        .o_data_parallel_ready 	(w_trunc_cache_ready  ),
        .o_data_serial         	(w_outmux_cache_data           ),
        .o_data_serial_valid   	(w_outmux_cache_valid    ),
        .i_data_serial_ready   	(w_outmux_cache_ready    ),
        .o_mem_full            	(o_mem_full             ),
        .o_mem_empty           	(o_mem_empty            )
    );

    BUS_MUX_A #(
        .D_WIDTH 	(D_WIDTH  ))
    u_BUS_OUTMUX(
        .data_a    	(w_outmux_cache_data     ),
        .valid_a   	(w_outmux_cache_valid    ),
        .ready_a   	(w_outmux_cache_ready    ),
        .data_b_0  	(w_dpmux_cache_data   ),
        .valid_b_0 	(w_dpmux_cache_valid  ),
        .ready_b_0 	(w_dpmux_cache_ready  ),
        .data_b_1  	(o_fc2cpa_data   ),
        .valid_b_1 	(o_fc2cap_valid  ),
        .ready_b_1 	(i_fc2cap_ready  ),
        .sel       	(i_out_mux_sel   )
    );
    

    // //layer_done逻辑
    // reg reg_layer_done = 0;
    // assign o_fc_layerdone = reg_layer_done;
    // localparam layerdone_high_period = 4;
    // reg [3:0] counter_layerdone = 0;
    // reg r_mem_full = 0;
    // reg r_mem_full_d = 0;
    // assign pos_memfull = (~r_mem_full_d) & r_mem_full;

    // always @(posedge clk or posedge o_mem_full)begin
    //     counter_layerdone <= (counter_layerdone == 0) ? 0 : (counter_layerdone - 1);
    //     if(pos_memfull == 1)begin
    //         counter_layerdone <= layerdone_high_period;
    //     end
    // end
    // always @(posedge clk)begin
    //         reg_layer_done =(counter_layerdone == 2) ? 1 : 0;
        
    // end
    
    //layer_done逻辑
    reg reg_layer_done = 0;
    assign o_fc_layerdone = reg_layer_done;
    localparam layerdone_high_period = 4;
    reg [3:0] counter_layerdone = 0;
    reg r_mem_full = 0;
    reg r_mem_full_d = 0;
    wire pos_memfull;
    assign pos_memfull = (~r_mem_full_d) & r_mem_full;

    // 先对 o_mem_full 进行打拍，检测上升沿
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_mem_full <= 0;
            r_mem_full_d <= 0;
        end else begin
            r_mem_full <= o_mem_full;
            r_mem_full_d <= r_mem_full;
        end
    end

    // 计数器逻辑
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter_layerdone <= 0;
        end else begin
            if (pos_memfull) begin
                counter_layerdone <= layerdone_high_period;
            end else if (counter_layerdone > 0) begin
                counter_layerdone <= counter_layerdone - 1;
            end
        end
    end

    // layer_done 信号生成
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_layer_done <= 0;
        end else begin
            reg_layer_done <= (counter_layerdone == 2) ? 1'b1 : 1'b0;
        end
    end

endmodule
