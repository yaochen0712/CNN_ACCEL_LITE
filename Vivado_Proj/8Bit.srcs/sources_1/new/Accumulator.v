module Accumulator 
#(
    parameter D_WIDTH = 32,
    parameter COUNT_WIDTH = $clog2(512),//最高支持512次
    parameter GATE_PARA = 2 ,//
    parameter CHANNEL_NUM = 128, //支持最大128通道
    parameter MULTIOUT_DWIDTH = 16,
    parameter CHANNEL_DATAWIDTH = 8
)
(
    input clk,
    input rst_n,

    input [COUNT_WIDTH-1:0] i_count_limit,//累加次数
    input [$clog2(GATE_PARA):0] i_cfg_gate_en,     // 门控使能配置
    input i_accumulator_cfg_en,//配置更新用
    
    //数据接口
    input [MULTIOUT_DWIDTH*CHANNEL_NUM-1:0] i_data_in,
    input i_data_in_valid,
    output reg o_data_in_ready,

    //BIAS 缓存接口
    input [CHANNEL_DATAWIDTH*CHANNEL_NUM-1:0] i_bias_in,
    input i_bias_in_valid,
    output reg o_bias_in_ready,

    //输出接口
    output [(D_WIDTH ) * CHANNEL_NUM - 1:0] o_data_out,
    output reg o_data_out_valid,
    input i_data_out_ready
);
    wire data_in_fire,data_out_fire,bias_fire;
    assign data_in_fire = i_data_in_valid & o_data_in_ready;
    assign data_out_fire = o_data_out_valid & i_data_out_ready;
    assign bias_fire = i_bias_in_valid & o_bias_in_ready;

    reg [$clog2(GATE_PARA):0] gate_en_reg;        // 门控配置寄存器
    reg [COUNT_WIDTH-1:0] count_limit_reg;  //累加次数寄存器
    reg config_received;  // 配置接收标志
    
    reg [15:0] counter;
    reg count_done;

    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            gate_en_reg <= 0;
            count_limit_reg <= 0;
            config_received <= 0;
        end
        else if(i_accumulator_cfg_en)begin
            gate_en_reg <= i_cfg_gate_en;
            count_limit_reg <= i_count_limit;
            config_received <= 1;  // 标记配置已接收
        end
        else if(data_in_fire && (counter == (1 << count_limit_reg) - 1))begin
            config_received <= 0;  // 累加完成后清除配置标志
        end
    end

    //BIAS BUFFER处理逻辑
    reg [CHANNEL_DATAWIDTH*CHANNEL_NUM-1:0] bias_buf;
    wire [CHANNEL_DATAWIDTH*CHANNEL_NUM-1:0] w_bias_buf;
    assign w_bias_buf = i_bias_in;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            bias_buf <= {(CHANNEL_DATAWIDTH*CHANNEL_NUM){1'b0}};
            o_bias_in_ready <= 1;
        end
        else if(bias_fire) begin
            bias_buf <= w_bias_buf;
            o_bias_in_ready <= 0;
        end
        else if(data_out_fire)begin
            o_bias_in_ready <= 1;
        end
    end
    

    //计数逻辑 - 修复版本
    always @(posedge clk or negedge rst_n) begin
        if(~rst_n)begin
            counter <= 0;
            count_done <= 0;
        end
        else begin

            // 正常累加
            if(data_in_fire)begin
                if(counter == (1 << count_limit_reg) - 1)begin
                    // 这次握手后刚好达到限制，置done信号
                    counter <= 0;  // 同时清零计数器（为下一轮准备）
                    count_done <= 1;
                end
                else begin
                    counter <= counter + 1;
                    count_done <= 0;
                end
            end
            else if(data_out_fire)begin           
             // 当count_done时（已输出），清零计数器和done信号
                counter <= 0;
                count_done <= 0;
            end
        end
    end

    // ========== 计算有效通道数 ==========
    wire [CHANNEL_NUM-1:0] channel_enable;
    wire [$clog2(CHANNEL_NUM):0] valid_channel_count;
    assign valid_channel_count = (CHANNEL_NUM >> GATE_PARA) << gate_en_reg;
    // 生成通道使能信号
    genvar i;
    generate
        for (i = 0; i < CHANNEL_NUM; i = i + 1) begin : gen_channel_enable
            assign channel_enable[i] = (i < valid_channel_count);
        end
    endgenerate

    // ========== 累加器单元信号 ==========
    wire [CHANNEL_NUM-1:0] acc_clear;
    wire [CHANNEL_NUM-1:0] acc_sum_out;
    wire [CHANNEL_NUM-1:0] acc_valid_in;
    wire [D_WIDTH*CHANNEL_NUM-1:0] acc_data_out;  
    wire [2*CHANNEL_NUM-1:0] acc_overflow;
    
    // 控制信号
    assign acc_clear = {CHANNEL_NUM{!rst_n}};
    assign acc_sum_out = {CHANNEL_NUM{count_done}};
    
    // 控制信号
    assign acc_clear = {CHANNEL_NUM{!rst_n}};
    assign acc_sum_out = {CHANNEL_NUM{count_done}};

    // ========== 例化累加器单元 ==========
    generate
        for (i = 0; i < CHANNEL_NUM; i = i + 1) begin : gen_accumulator_units
            assign acc_valid_in[i] = data_in_fire & channel_enable[i];
            
            Accumulator_unit #(
                .DIN_WIDTH(MULTIOUT_DWIDTH),
                .DOUT_WIDTH(D_WIDTH)  
            ) u_acc_unit (
                .clk(clk),
                .clear(acc_clear[i]),
                .i_data_in(i_data_in[MULTIOUT_DWIDTH*i +: MULTIOUT_DWIDTH]),
                .i_data_in_valid(acc_valid_in[i]),
                .i_sum_out(acc_sum_out[i]),
                .o_data_out(acc_data_out[D_WIDTH*i +: D_WIDTH]),  
                .o_accumulator_overflow(acc_overflow[2*i +: 2])
            );
        end
    endgenerate

    // ========== BIAS 加法（组合逻辑） ==========
    wire [D_WIDTH*CHANNEL_NUM-1:0] data_with_bias;
    
    generate
        for (i = 0; i < CHANNEL_NUM; i = i + 1) begin : gen_bias_add
            assign data_with_bias[D_WIDTH*i +: D_WIDTH] = 
                acc_data_out[D_WIDTH*i +: D_WIDTH] + 
                {{(D_WIDTH-CHANNEL_DATAWIDTH){bias_buf[CHANNEL_DATAWIDTH*i + CHANNEL_DATAWIDTH-1]}}, 
                 bias_buf[CHANNEL_DATAWIDTH*i +: CHANNEL_DATAWIDTH]};
        end
    endgenerate

    //输出
    //锁存部分
    reg count_done_delay;//延迟一拍
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            count_done_delay <= 0;
        end
        else begin
            count_done_delay <= count_done;
        end
    end
    reg [D_WIDTH*CHANNEL_NUM-1:0] data_out_reg;
    assign o_data_out = data_out_reg;
    always @(posedge count_done_delay or negedge rst_n) begin
        if(!rst_n) begin
            data_out_reg <= 0;
        end
        else if(count_done_delay) begin
            data_out_reg <= data_with_bias;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            o_data_out_valid <= 0;
        end
        else if(data_out_fire) begin
            o_data_out_valid <= 0;
        end
        else if(count_done) begin
            o_data_out_valid <= 1;
        end
    end

    //上游dataready逻辑 - 合理的反压控制
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            o_data_in_ready <= 0;  // 复位后ready为0，等待配置
        end
        else if(i_accumulator_cfg_en) begin
            // 配置时，如果有未取走的输出则保持ready为0，否则拉高
            if(o_data_out_valid) begin
                o_data_in_ready <= 0;  // 有未取走的结果，等待下游取走
            end else begin
                o_data_in_ready <= 1;  // 可以开始新的累加
            end
        end
        else if(data_out_fire) begin
            // 输出被取走后，如果已配置且不是刚累加完成，则拉高ready
            if(config_received && !count_done) begin
                o_data_in_ready <= 1;
            end
        end
        else if(data_in_fire && counter == (1 << count_limit_reg) - 1) begin
            o_data_in_ready <= 0;  // 累加完成后拉低ready，等待输出被取走
        end
    end
endmodule