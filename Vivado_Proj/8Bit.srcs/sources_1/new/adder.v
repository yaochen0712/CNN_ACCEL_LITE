`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: adder
// Description: 可配置位宽的有符号加法器
//              - 支持位宽扩展（DOUT_WIDTH > DIN_WIDTH）
//              - 支持位宽截断（DOUT_WIDTH < DIN_WIDTH）
//              - 溢出检测
//////////////////////////////////////////////////////////////////////////////////

module adder
#(
    parameter DIN_WIDTH = 16,      // 使用parameter而不是localparam
    parameter DOUT_WIDTH = 32      // 支持截位和扩位
)
(
    // 输入信号
    input signed [DIN_WIDTH-1:0] i_data_a,
    input signed [DIN_WIDTH-1:0] i_data_b,

    // 输出信号
    output signed [DOUT_WIDTH-1:0] o_data_sum,
    output o_overflow
);

    // ========== 内部信号 ==========
    // 扩展1位用于溢出检测
    wire signed [DIN_WIDTH:0] temp_sum;
    
    // ========== 加法计算 ==========
    // 将两个输入扩展1位后相加，避免溢出
    assign temp_sum = {i_data_a[DIN_WIDTH-1], i_data_a} + {i_data_b[DIN_WIDTH-1], i_data_b};
    
    // ========== 位宽处理 ==========
    generate
        if (DOUT_WIDTH > DIN_WIDTH + 1) begin : EXTEND_WIDTH
            // 输出位宽大于输入+1：符号扩展
            // 例如：DIN=16, DOUT=32 → 扩展15位符号位
            assign o_data_sum = {{(DOUT_WIDTH-DIN_WIDTH-1){temp_sum[DIN_WIDTH]}}, temp_sum};
            
        end else if (DOUT_WIDTH == DIN_WIDTH + 1) begin : EXACT_WIDTH
            // 输出位宽正好是输入+1：直接使用temp_sum
            assign o_data_sum = temp_sum;
            
        end else begin : TRUNCATE_WIDTH
            // 输出位宽小于等于输入：截断高位
            // 例如：DIN=16, DOUT=8 → 只取低8位
            assign o_data_sum = temp_sum[DOUT_WIDTH-1:0];
        end
    endgenerate
    
    // ========== 溢出检测 ==========
    // 溢出条件：
    // 1. 两个操作数符号相同
    // 2. 结果符号与操作数符号不同
    // 3. 输出位宽不足以表示结果（DOUT_WIDTH <= DIN_WIDTH）
    assign o_overflow = (i_data_a[DIN_WIDTH-1] == i_data_b[DIN_WIDTH-1]) && 
                       (temp_sum[DIN_WIDTH] != temp_sum[DIN_WIDTH-1]) && 
                       (DOUT_WIDTH <= DIN_WIDTH);

endmodule