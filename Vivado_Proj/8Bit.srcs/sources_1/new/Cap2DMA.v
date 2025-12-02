`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/12/03 00:49:45
// Design Name: 
// Module Name: Cap2DMA
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


module Cap2DMA
#(
    parameter DATA_WIDTH = 32,
    parameter DEST_WIDTH = 4,
    parameter ID_WIDTH = 4,
    parameter USER_WIDTH = 1
)
(
    input wire clk,
    input wire rst_n,
    
    // 来自PL运算结果的输入接口（32bit数据：2个8bit结果+判断数据填充）
    input wire [DATA_WIDTH-1:0]                 i_data_in,
    input wire                                  i_data_in_valid,
    output reg                                  o_data_in_ready,
    
    // AXI4-Stream Master Interface (连接到AXI DMA的S2MM)
    output reg [DATA_WIDTH-1:0]                 m_axis_tdata,
    output wire [DATA_WIDTH/8-1:0]              m_axis_tstrb,
    output wire [DATA_WIDTH/8-1:0]              m_axis_tkeep,
    output reg                                  m_axis_tvalid,
    input  wire                                 m_axis_tready,
    output reg                                  m_axis_tlast,
    output wire [ID_WIDTH-1:0]                  m_axis_tid,
    output wire [DEST_WIDTH-1:0]                m_axis_tdest,
    output wire [USER_WIDTH-1:0]                m_axis_tuser

);

    // AXI4-Stream固定信号
    assign m_axis_tstrb = {(DATA_WIDTH/8){1'b1}};  // 全部字节有效
    assign m_axis_tkeep = {(DATA_WIDTH/8){1'b1}};  // 全部字节保持
    assign m_axis_tid   = {ID_WIDTH{1'b0}};        // ID固定为0
    assign m_axis_tdest = {DEST_WIDTH{1'b0}};      // 目的地固定为0
    assign m_axis_tuser = {USER_WIDTH{1'b0}};      // 用户信号固定为0
    
    // 握手信号
    wire axis_handshake;
    assign axis_handshake = m_axis_tvalid && m_axis_tready;
    
    wire input_handshake;
    assign input_handshake = i_data_in_valid && o_data_in_ready;
    
    // 状态机定义
    localparam IDLE       = 1'd0;
    localparam SENDING    = 1'd1;
    
    reg state, next_state;
    
    // 数据缓存（直接缓存32bit数据）
    reg [DATA_WIDTH-1:0] data_buffer;
    
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
                if (input_handshake) begin
                    next_state = SENDING;
                end
            end
            
            SENDING: begin
                if (axis_handshake) begin
                    next_state = IDLE;
                end
            end
        endcase
    end
    
    // 数据缓存逻辑（直接锁存32bit输入）
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_buffer <= {DATA_WIDTH{1'b0}};
        end else if (input_handshake) begin
            data_buffer <= i_data_in;  // 直接缓存32bit数据
        end
    end
    
    // 上游ready信号
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_data_in_ready <= 1'b1;  // 初始可以接收
        end else begin
            case (state)
                IDLE: begin
                    o_data_in_ready <= 1'b1;  // IDLE状态可以接收新数据
                end
                SENDING: begin
                    o_data_in_ready <= 1'b0;  // 发送时停止接收
                end
            endcase
        end
    end
    
    // AXI-Stream输出信号
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axis_tdata  <= {DATA_WIDTH{1'b0}};
            m_axis_tvalid <= 1'b0;
            m_axis_tlast  <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    m_axis_tvalid <= 1'b0;
                    m_axis_tlast  <= 1'b0;
                end
                
                SENDING: begin
                    m_axis_tdata  <= data_buffer;
                    m_axis_tvalid <= 1'b1;
                    m_axis_tlast  <= 1'b1;  // 简化：每次都是单个32bit传输
                    
                    if (axis_handshake) begin
                        m_axis_tvalid <= 1'b0;
                        m_axis_tlast  <= 1'b0;
                    end
                end
            endcase
        end
    end

endmodule
