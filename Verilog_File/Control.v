`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/11/01 23:05:24
// Design Name: 
// Module Name: Control
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


module Control
#(
    parameter MAX_LAYER = 8,
    parameter INPUT_CHANNEL_MAXNUM = 512,
    parameter ACCUMULATOR_OUTWIDTH = 24,
    parameter MAX_OUTPUT_LAYER = 128,//中间计算输出层最多128
    parameter GATE_MIN_SCALE_COEF = 6, //以两个通道为粒度进行控制 128/2^6 可以开启2-4-8-16.....-128
    parameter D_WIDTH = 8
)
(
    input clk,
    input rst_n,
    input i_layer_error,
    output o_layer_en,//启动计算
    output o_soc_error,

    //指令流接口
    input i_command_valid,
    input [15:0] i_command_data,
    output o_command_ready,

    //层数通路控制
    input i_layer_done,
    output  o_dp_sel,//选择是从FIFO还是Cache读取
    output  [$clog2(MAX_LAYER)-1:0] o_layer_idx,//存储采用多块RAM节省

    //配置端口
    output  o_accumulator_cfg_en,
    output [$clog2(INPUT_CHANNEL_MAXNUM)-1:0] o_accumulator_cfg_channel_innum,//就是累加器要加多少次
    output [$clog2(GATE_MIN_SCALE_COEF):0] o_accumulator_cfg_gate,//门控信号

    output  o_trunction_cfg_en,
    output  [$clog2(ACCUMULATOR_OUTWIDTH-D_WIDTH)-1:0] o_trunction_cfg_lsb_idx,
    output  o_trunction_cfg_saturate_en,
    output  o_relu_en,

    output o_n_bram_setaddr_zero
    );

    reg [$clog2(MAX_LAYER)-1:0] layer_count;//类似于PC
    reg [3:0] reconfig_counter;
    localparam RECONFIG_PERIOD = 4;//重新配置周期 
    reg [2:0] state,next_state,prev_state;
    localparam RST = 3'd0,FETCH =3'd1, ASIC_CONFIG =3'd2, WAIT_DONE=3'd3, FINISH=3'd4 , ERROR = 3'd5, RECFG= 3'd6;
    
    wire fetch_fire;
    assign fetch_fire = i_command_valid & o_command_ready;
    reg o_reg_command_ready;
    assign o_command_ready = o_reg_command_ready;
    //o_command_ready
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            o_reg_command_ready <= 0;
        end
        else if(state == FETCH)begin
            o_reg_command_ready <= fetch_fire ? 0 : 1;
        end
    end 

    //COMMAND_FETCH
    reg [(16-1):0] command_latch;
    always @(posedge clk)begin
        if(state == FETCH & i_command_valid)begin
            command_latch <= i_command_data;
        end
    end

    //layer_counter refresh
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            layer_count <= 0;
        end
        else begin
            if(prev_state == WAIT_DONE & ((state == FETCH) | (state == FINISH)))begin
                layer_count <= layer_count + 1;
            end
        end
    end

    //DECODE
    reg [1:0] layer_tag;
    reg [3:0] layer_innum;
    reg [3:0] layer_outnum;
    reg relu_en;
    reg [2:0] lsb_trunc_pos;
    reg trunc_en;
    assign o_dp_sel = (layer_tag==2'b00);
    assign o_layer_idx = layer_count;
    assign o_accumulator_cfg_channel_innum = layer_innum;
    assign o_accumulator_cfg_gate = $clog2(MAX_OUTPUT_LAYER) - layer_outnum;
    assign o_trunction_cfg_saturate_en = trunc_en;
    assign o_trunction_cfg_lsb_idx = lsb_trunc_pos;
    assign o_relu_en = relu_en;
    always @(posedge clk)begin
        if((state == ASIC_CONFIG) & (prev_state == FETCH))begin
            layer_tag <= command_latch[1:0];
            layer_innum <= command_latch[5:2];
            layer_outnum <= command_latch[9:6];
            relu_en <= command_latch[10];
            lsb_trunc_pos <= command_latch[13:11];
            trunc_en <= command_latch[14];
        end
    end

    //配置写入
    localparam CONFIG_PEROID = 3;//配置写入四个周期 ASIC_CONFIG状态维持4个周期
    reg [$clog2(CONFIG_PEROID):0] cfg_p_cnt;
    always @(posedge clk)begin
        if(state == ASIC_CONFIG)begin
            cfg_p_cnt <= cfg_p_cnt + 1;
        end
        else begin
            cfg_p_cnt <= 0;
        end
    end
    reg cfg_en;
    assign o_accumulator_cfg_en = cfg_en;
    assign o_trunction_cfg_en = cfg_en;
    always @(posedge clk)begin
        if(state == ASIC_CONFIG)begin
            cfg_en <= (cfg_p_cnt < CONFIG_PEROID)? 1 : 0 ;
        end
        else begin
            cfg_en = 0;
        end
    end

    //一层计算完成后的重新配置处理
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            reconfig_counter <= RECONFIG_PERIOD;
        end
        else begin
            if(state == RECFG)begin
                reconfig_counter <= (reconfig_counter != 0) ? reconfig_counter - 1 : 0;
            end
            else begin
                reconfig_counter <= RECONFIG_PERIOD;
            end
        end
    end

    reg reg_rstn_ctrl;
    reg [1:0] rstn_ctrl_counter;
    localparam RSTN_CTRL_PERIOD = 2;//rstn_ctrl拉低周期
    assign o_n_bram_setaddr_zero = reg_rstn_ctrl;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            reg_rstn_ctrl <= 1;
            rstn_ctrl_counter <= RSTN_CTRL_PERIOD;
        end
        else begin
            if(state == RECFG)begin
                reg_rstn_ctrl <= (rstn_ctrl_counter != 0) ? 0 : 1;
                rstn_ctrl_counter <= (rstn_ctrl_counter == 0) ? 0 : rstn_ctrl_counter - 1;
            end
            else begin
                reg_rstn_ctrl <= 1;
                rstn_ctrl_counter <= RSTN_CTRL_PERIOD;
            end
        end
    end


    //状态转移
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state <= RST;
        end
        else begin
            state <= next_state;
            prev_state <= state;
        end
    end
    always @(*)begin
        next_state = ERROR;
        case (state)
            RST:next_state = FETCH;
            FETCH:next_state = (fetch_fire) ? ASIC_CONFIG : FETCH;
            ASIC_CONFIG: next_state = (cfg_p_cnt >= CONFIG_PEROID) ? WAIT_DONE : ASIC_CONFIG;
            WAIT_DONE:next_state = (i_layer_done) ? ((layer_tag == 2'b11) ? FINISH : FETCH) : WAIT_DONE;
            FINISH:next_state = RECFG;
            RECFG:next_state = (reconfig_counter == 0) ? FETCH : RECFG;
            ERROR:next_state = ERROR;
        endcase
        if(i_layer_error)begin
            next_state <= ERROR;
        end
    end

    //启动计算 
    reg reg_calc_en;
    assign o_layer_en = reg_calc_en;
    always @(posedge clk)begin
        if(state == WAIT_DONE)begin
            reg_calc_en <= 1;
        end
        else begin
            reg_calc_en <= 0;
        end
    end

    //错误处理
    reg reg_o_soc_error;
    assign o_soc_error = reg_o_soc_error;
    always @(posedge clk) begin
        reg_o_soc_error <= (state == ERROR);
    end
    
endmodule
