`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: trunction
// Description: 可配置的截位模块，支持动态LSB起始位和饱和处理（有符号数版本）
//              - 时序逻辑实现，配合valid-ready握手
//              - 支持配置更新和数据流水
//              - i_trunction_cfg_lsb_idx: 配置从哪个LSB位开始截取
//              - i_trunction_cfg_saturate_en: 配置是否启用饱和处理
//              - 支持有符号数的符号扩展和饱和处理
//////////////////////////////////////////////////////////////////////////////////

module trunction 
#(
    parameter DIN_WIDTH = 32,
    parameter DOUT_WIDTH = 8
)
(
    input wire clk,
    input wire rst_n,
    
    // 上游数据接口
    input  wire signed [DIN_WIDTH-1:0] i_din,
    input  wire i_din_valid,
    output reg  o_din_ready,
    
    // 下游数据接口
    output reg signed [DOUT_WIDTH-1:0] o_dout,
    output reg o_dout_valid,
    input  wire i_dout_ready,
    
    // 配置接口
    input wire [$clog2(DIN_WIDTH-DOUT_WIDTH):0] i_trunction_cfg_lsb_idx,
    input wire i_trunction_cfg_saturate_en,
    input wire i_trunction_cfg_en
);

    // 配置寄存器
    reg [$clog2(DIN_WIDTH)-1:0] lsb_start;
    reg saturate_en;

    // 内部信号
    reg signed [DIN_WIDTH-1:0] shifted_data;
    reg pos_overflow, neg_overflow;
    reg signed [DOUT_WIDTH-1:0] truncated_data;
    
    // 饱和值定义
    localparam signed [DOUT_WIDTH-1:0] MAX_POS = {1'b0, {(DOUT_WIDTH-1){1'b1}}};  // 0111...1 (最大正数)
    localparam signed [DOUT_WIDTH-1:0] MAX_NEG = {1'b1, {(DOUT_WIDTH-1){1'b0}}};  // 1000...0 (最小负数)
    
    integer i;
    
    // 配置更新逻辑
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lsb_start <= {$clog2(DIN_WIDTH){1'b0}};
            saturate_en <= 1'b0;
        end else if (i_trunction_cfg_en) begin
            lsb_start <= i_trunction_cfg_lsb_idx;
            saturate_en <= i_trunction_cfg_saturate_en;
        end
    end
    
    // 握手信号：组合逻辑透传
    always @(*) begin
        o_din_ready = i_dout_ready;
        o_dout_valid = i_din_valid;
    end
    
    // 截位和溢出检测（组合逻辑）
    always @(*) begin
        // 步骤1: 根据lsb_start进行算术右移（保持符号）
        shifted_data = i_din >>> lsb_start;
        
        // 步骤2: 提取低DOUT_WIDTH位
        truncated_data = shifted_data[DOUT_WIDTH-1:0];
        
        // 步骤3: 检测正向和负向溢出
        pos_overflow = 1'b0;
        neg_overflow = 1'b0;
        
        if (shifted_data[DIN_WIDTH-1] == 1'b0) begin
            // 正数：检查高位是否有1
            for (i = DOUT_WIDTH; i < DIN_WIDTH; i = i + 1) begin
                if (shifted_data[i] == 1'b1) begin
                    pos_overflow = 1'b1;
                end
            end
        end else begin
            // 负数：检查高位是否全为1（符号扩展）
            for (i = DOUT_WIDTH; i < DIN_WIDTH; i = i + 1) begin
                if (shifted_data[i] == 1'b0) begin
                    neg_overflow = 1'b1;
                end
            end
        end
        
        // 额外检查：如果截位后的符号位与原始符号不匹配，也是溢出
        if (shifted_data[DIN_WIDTH-1] != truncated_data[DOUT_WIDTH-1]) begin
            if (shifted_data[DIN_WIDTH-1] == 1'b0) begin
                pos_overflow = 1'b1;  // 正数变成了负数
            end else begin
                neg_overflow = 1'b1;  // 负数变成了正数
            end
        end
    end
    
    // 数据输出组合逻辑
    always @(*) begin
        if (saturate_en) begin
            if (pos_overflow) begin
                o_dout = MAX_POS;  // 饱和到最大正数
            end else if (neg_overflow) begin
                o_dout = MAX_NEG;  // 饱和到最小负数
            end else begin
                o_dout = truncated_data;  // 正常截位
            end
        end else begin
            o_dout = truncated_data;  // 不启用饱和，直接截位
        end
    end

endmodule