`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/10/08 15:22:22
// Design Name: 
// Module Name: ReLU
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: ReLU activation function with handshake control
//              Output = max(0, input)
//              - Supports configurable bit width
//              - Valid/Ready handshake protocol
//              - Zero latency (combinational ReLU)
//              - Optional pipeline register for timing optimization
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module ReLU #(
    parameter DATA_WIDTH = 32,      // 数据位宽
    parameter PIPELINE = 0          // 0: 组合逻辑, 1: 插入流水线寄存器
)
(
    input clk,
    input rst_n,
    
    // 输入端口
    input signed [DATA_WIDTH-1:0] i_data_in,
    input i_data_in_valid,
    output i_data_in_ready,
    
    // 输出端口
    output signed [DATA_WIDTH-1:0] o_data_out,
    output o_data_out_valid,
    input o_data_out_ready,

    //Relu配置
    input i_cfg_en,
    input i_relu_cfg
);

    // ========== 握手控制信号 ==========
    wire input_fire;
    wire output_fire;
    reg ready_reg;
    
    assign input_fire = i_data_in_valid && ready_reg;
    assign output_fire = o_data_out_valid && o_data_out_ready;
    assign i_data_in_ready = ready_reg;
    //配置
    reg relu_en_reg;
    always @(posedge clk) begin
        if(i_cfg_en)begin
            relu_en_reg <= i_relu_cfg;
        end
    end
    
    // ========== Ready信号控制 ==========
    // 上电默认就绪,只在输出反压时拉低
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ready_reg <= 1'b1;  // 
        end else begin
            if (o_data_out_valid && !o_data_out_ready) begin
                // 下游反压时拉低ready
                ready_reg <= 1'b0;
            end else begin
                // 其他情况保持就绪
                ready_reg <= 1'b1;
            end
        end
    end
    
    // ========== ReLU功能实现 ==========
    wire signed [DATA_WIDTH-1:0] relu_result;
    
    // ReLU: 如果输入为负则输出0,否则输出原值
    assign relu_result = (i_data_in[DATA_WIDTH-1] == 1'b1) ? {DATA_WIDTH{1'b0}} : i_data_in;
    
    // ========== 流水线选择 ==========
    generate
        if (PIPELINE == 0) begin : NO_PIPELINE
            // ========== 组合逻辑模式(零延迟) ==========
            assign o_data_out = (relu_en_reg ? relu_result : i_data_in);
            assign o_data_out_valid = i_data_in_valid;
            
        end else begin : WITH_PIPELINE
            // ========== 流水线寄存器模式(1周期延迟) ==========
            reg signed [DATA_WIDTH-1:0] o_data_out_reg;
            reg o_data_out_valid_reg;
            
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    o_data_out_reg <= {DATA_WIDTH{1'b0}};
                    o_data_out_valid_reg <= 1'b0;
                end else begin
                    // 流水线推进:ready有效或输出握手时
                    if (ready_reg || output_fire) begin
                        o_data_out_reg <= relu_result;
                        
                        // Valid控制
                        if (output_fire) begin
                            // 握手完成后,检查是否有新输入
                            o_data_out_valid_reg <= input_fire;
                        end else if (input_fire && !o_data_out_valid_reg) begin
                            // 新数据到达,拉高valid
                            o_data_out_valid_reg <= 1'b1;
                        end
                        // else: 保持当前状态(反压期间valid保持高电平)
                    end
                end
            end
            
            assign o_data_out = (relu_en_reg ? o_data_out_reg : i_data_in);
            assign o_data_out_valid = o_data_out_valid_reg;
        end
    endgenerate

endmodule
