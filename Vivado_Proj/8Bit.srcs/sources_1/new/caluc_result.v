`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: caluc_result
// Description: 串行接收两个8bit有符号数据A和B，比较大小后格式化输出
//              - 输入：串行接收（先A后B）
//              - 比较：判断A>B，结果为1bit（A大为1，否则为0）
//              - 输出：32bit数据 = {16{比较结果}, A[7:0], B[7:0]}
//              - 用途：将FC层的两个分类结果比较后，格式化输出给Cap2DMA模块
//////////////////////////////////////////////////////////////////////////////////

module calc_result(
    input clk,
    input rst_n,

    //2 Cache - 串行输入接口
    input [7:0] i_result_data_in,
    input i_result_data_valid,
    output reg o_result_data_ready,

    //2 DMA - 输出接口
    output reg [31:0] o_trans_data,
    output reg o_trans_valid,
    input i_trans_ready
);

    // 握手信号
    wire input_handshake;
    wire output_handshake;
    assign input_handshake = i_result_data_valid && o_result_data_ready;
    assign output_handshake = o_trans_valid && i_trans_ready;
    
    // 状态机定义
    localparam IDLE       = 2'd0;
    localparam RECV_A     = 2'd1;
    localparam RECV_B     = 2'd2;
    localparam SENDING    = 2'd3;
    
    reg [1:0] state, next_state;
    
    // 数据寄存器
    reg signed [7:0] data_a_reg;
    reg signed [7:0] data_b_reg;
    reg compare_result;  // A>B ? 1 : 0
    
    // 状态机 - 当前状态
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end
    
    // 状态机 - 次态逻辑
    always @(*) begin
        next_state = state;
        case (state)
            IDLE: begin
                next_state = RECV_A;
            end
            
            RECV_A: begin
                if (input_handshake) begin
                    next_state = RECV_B;
                end
            end
            
            RECV_B: begin
                if (input_handshake) begin
                    next_state = SENDING;
                end
            end
            
            SENDING: begin
                if (output_handshake) begin
                    next_state = RECV_A;  // 继续接收下一组数据
                end
            end
        endcase
    end
    
    // 数据接收逻辑 - 串行接收A和B
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_a_reg <= 8'sd0;
            data_b_reg <= 8'sd0;
        end else begin
            if (state == RECV_A && input_handshake) begin
                data_a_reg <= $signed(i_result_data_in);
            end else if (state == RECV_B && input_handshake) begin
                data_b_reg <= $signed(i_result_data_in);
            end
        end
    end
    
    // 比较逻辑 - 在接收完B后立即比较
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            compare_result <= 1'b0;
        end else if (state == RECV_B && input_handshake) begin
            compare_result <= (data_a_reg > $signed(i_result_data_in)) ? 1'b1 : 1'b0;
        end
    end
    
    // 上游ready信号
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_result_data_ready <= 1'b0;
        end else begin
            case (state)
                RECV_A: begin
                    o_result_data_ready <= 1'b1;  // 等待接收A
                end
                RECV_B: begin
                    o_result_data_ready <= 1'b1;  // 等待接收B
                end
                default: begin
                    o_result_data_ready <= 1'b0;
                end
            endcase
        end
    end
    
    // 输出数据拼接和valid信号
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_trans_data <= 32'd0;
            o_trans_valid <= 1'b0;
        end else begin
            case (state)
                SENDING: begin
                    // 按照 {16{比较结果}, A[7:0], B[7:0]} 拼接
                    o_trans_data <= {{16{compare_result}}, data_a_reg, data_b_reg};
                    o_trans_valid <= 1'b1;
                    
                    if (output_handshake) begin
                        o_trans_valid <= 1'b0;
                    end
                end
                
                default: begin
                    o_trans_valid <= 1'b0;
                end
            endcase
        end
    end

endmodule
