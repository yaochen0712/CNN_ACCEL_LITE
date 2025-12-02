`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/11/01 23:12:51
// Design Name: 
// Module Name: config
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

`ifndef CONFIG_V
`define CONFIG_V

`define ACCUMULATOR_OUTWIDTH 32 //累加器输出32bit
`define CTRL_LAYER_MAX 8 //模块最多支持8层的数据复用
`define TRUNCTION_PIPE_MODE 1 //采用流水模式而非assign语句
`define INPUT_CHANNEL_NUM 512 //每次输入512通道
`define CHANNEL_DATAWIDTH 8 //总体采用8bit
`define O_MULTIPLIER_DATAWIDTH 16 //乘法器位宽8bit
`define MAX_PARRAL_CHANNEL 128 //最大并行处理通道数
`define CHANNEL_GATE_PARA 4 //通道门控参数,表示将累加器分成四组进行GATING门控

`endif