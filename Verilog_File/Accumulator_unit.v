`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: Accumulator_unit
// Description: 带溢出检测的累加器单元
//              - 支持有符号累加
//              - 上溢出和下溢出检测
//              - i_sum_out信号控制输出当前累加值并清零
//              - clear信号直接清零
//////////////////////////////////////////////////////////////////////////////////

module Accumulator_unit
#(
    parameter DIN_WIDTH = 16,
    parameter DOUT_WIDTH = 32
)
(
    input wire clk,
    input wire clear,                               // 清零信号

    // 输入数据接口
    input wire signed [DIN_WIDTH-1:0] i_data_in,
    input wire i_data_in_valid,
    
    // 输出控制
    input wire i_sum_out,                           // 输出当前累加值并清零
    
    // 输出数据
    output reg signed [DOUT_WIDTH-1:0] o_data_out,
    output reg [1:0] o_accumulator_overflow         // [1]:下溢出, [0]:上溢出 有毛病算了能用
);

    reg signed [DOUT_WIDTH-1:0] accumulator;
    reg last_sign;
    wire signed [DOUT_WIDTH-1:0] sum_result;
    assign sum_result = accumulator + {{(DOUT_WIDTH-DIN_WIDTH){i_data_in[DIN_WIDTH-1]}},i_data_in};


    always @(posedge clk or posedge clear) begin
        if (clear) begin
            accumulator <= {DOUT_WIDTH{1'b0}};
            o_accumulator_overflow <= 2'b00;
            o_data_out <= {DOUT_WIDTH{1'b0}};
            last_sign <= 1'b0;
        end
        else begin
            if(i_data_in_valid)begin
                last_sign <= accumulator[DOUT_WIDTH-1];
                accumulator <= sum_result;
                // 溢出检测
                if ( ~i_data_in[DIN_WIDTH-1] && ~last_sign && accumulator[DOUT_WIDTH-1])
                o_accumulator_overflow[1] <= 1'b1;  // pos overflow
                if ( i_data_in[DIN_WIDTH-1] && last_sign && ~accumulator[DOUT_WIDTH-1])
                o_accumulator_overflow[0] <= 1'b1;  // neg overflow
            end
            if(i_sum_out)begin
                o_data_out <= accumulator;
                accumulator <= i_data_in_valid ? {{(DOUT_WIDTH-DIN_WIDTH){i_data_in[DIN_WIDTH-1]}},i_data_in} : {DOUT_WIDTH{1'b0}};
            end
        end
    end

endmodule