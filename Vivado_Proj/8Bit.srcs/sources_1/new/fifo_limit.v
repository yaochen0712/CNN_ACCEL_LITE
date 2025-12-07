`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: Data_Buffer
// Description: 数据缓存模块，用于FC层的输入数据管理
//              - 从上游读取可配置数量的8bit数据并缓存
//              - 通过valid/ready协议与FC模块握手输出
//              - 支持控制器的重置控制（下降沿重置，上升沿开始发送）
//              - 当缓存满后停止上游读取
//              
// 工作流程：
//   1. 复位后，开始从上游读取数据填充缓存
//   2. 缓存满后(达到BUFFER_DEPTH)，拉低上游ready
//   3. 等待控制信号的上升沿触发
//   4. 触发后，向下游FC模块逐个发送缓存数据
//   5. 全部发送完毕后，清空缓存，重新读取上游
//   6. 如果控制信号下降沿到来，立即停止发送并重置
//////////////////////////////////////////////////////////////////////////////////

module Data_Buffer
#(
    parameter DATA_WIDTH = 8,           // 数据位宽
    parameter BUFFER_DEPTH = 512,       // 缓存深度（可配置）
    parameter ADDR_WIDTH = $clog2(BUFFER_DEPTH)
)
(
    input wire clk,
    input wire rst_n,
    
    // 控制信号（来自Controller）
    input wire i_ctrl_enable,  // 控制使能信号，posedge触发发送
    
    // 上游输入接口
    input wire [DATA_WIDTH-1:0]  i_data_in,
    input wire                   i_data_in_valid,
    output reg                   o_data_in_ready,
    
    // 下游输出接口（连接到FC模块）
    output reg [DATA_WIDTH-1:0]  o_data_out,
    output reg                   o_data_out_valid,
    input wire                   i_data_out_ready
);

    // 握手信号
    wire input_handshake;
    wire output_handshake;
    assign input_handshake = i_data_in_valid && o_data_in_ready;
    assign output_handshake = o_data_out_valid && i_data_out_ready;
    
    // 状态机定义
    localparam IDLE       = 3'd0;
    localparam FILLING    = 3'd1;
    localparam SENDING    = 3'd2;
    localparam WAIT_TRIG  = 3'd3;
    localparam REFILLING  = 3'd4;
    
    reg [2:0] state, next_state;
    reg first_run;  // 首次运行标志
    
    // 缓存存储器
    reg [DATA_WIDTH-1:0] buffer_mem [0:BUFFER_DEPTH-1];
    
    // 地址计数器
    reg [ADDR_WIDTH-1:0] write_addr;  // 写地址
    reg [ADDR_WIDTH-1:0] read_addr;   // 读地址
    reg buffer_full;                  // 缓存满标志
    reg buffer_empty;                 // 缓存空标志
    
    // 控制信号边沿检测
    reg ctrl_enable_d1;
    reg ctrl_enable;
    wire ctrl_posedge;
    wire ctrl_negedge;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ctrl_enable_d1 <= 1'b0;
        end else begin
            ctrl_enable <= i_ctrl_enable;
            ctrl_enable_d1 <= ctrl_enable;
        end
    end
    
    assign ctrl_posedge = i_ctrl_enable && !ctrl_enable_d1;   // 上升沿
    assign ctrl_negedge = !i_ctrl_enable && ctrl_enable_d1;   // 下降沿
    
    // 状态机 - 当前状态
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
        end else if (ctrl_negedge && state == SENDING) begin
            state <= IDLE;  // 只在SENDING状态时下降沿才重置
        end else begin
            state <= next_state;
        end
    end
    
    // 首次运行标志管理
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            first_run <= 1'b1;
        end else if (state == SENDING && buffer_empty && output_handshake) begin
            first_run <= 1'b0;  // 首次发送完成后清除标志
        end
    end
    
    // 状态机 - 次态逻辑
    always @(*) begin
        next_state = state;
        case (state)
            IDLE: begin
                next_state = FILLING;
            end
            
            FILLING: begin
                if (buffer_full) begin
                    if (first_run) begin
                        next_state = SENDING;  // 首次满了直接发送
                    end else begin
                        next_state = WAIT_TRIG;  // 后续需要等待触发
                    end
                end
            end
            
            SENDING: begin
                if (read_addr == BUFFER_DEPTH - 1 && output_handshake) begin
                    next_state = REFILLING;  // 发送完最后一个数据后重新填充
                end
            end
            
            WAIT_TRIG: begin
                if (ctrl_posedge && state == WAIT_TRIG) begin  // 只在WAIT_TRIG状态响应上升沿
                    next_state = SENDING;
                end
            end
            
            REFILLING: begin
                if (buffer_full) begin
                    next_state = WAIT_TRIG;  // 填充满后等待触发
                end
            end
        endcase
    end
    
    // 写地址计数器
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_addr <= {ADDR_WIDTH{1'b0}};
        end else begin
            case (state)
                IDLE: begin
                    write_addr <= {ADDR_WIDTH{1'b0}};
                end
                
                FILLING, REFILLING: begin
                    if (input_handshake) begin
                        if (write_addr == BUFFER_DEPTH - 1) begin
                            write_addr <= write_addr;  // 保持
                        end else begin
                            write_addr <= write_addr + 1'b1;
                        end
                    end
                end
                
                SENDING: begin
                    if (next_state == REFILLING) begin
                        write_addr <= {ADDR_WIDTH{1'b0}};  // 即将进入REFILLING，提前重置
                    end
                end
                
                WAIT_TRIG: begin
                    // 保持write_addr
                end
            endcase
        end
    end
    
    // 读地址计数器
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_addr <= {ADDR_WIDTH{1'b0}};
        end else begin
            case (state)
                IDLE: begin
                    read_addr <= {ADDR_WIDTH{1'b0}};
                end
                
                REFILLING: begin
                    read_addr <= {ADDR_WIDTH{1'b0}};
                end
                
                SENDING: begin
                    if (output_handshake) begin
                        if (read_addr == BUFFER_DEPTH - 1) begin
                            read_addr <= read_addr;  // 保持
                        end else begin
                            read_addr <= read_addr + 1'b1;
                        end
                    end
                end
            endcase
        end
    end
    
    // 缓存满/空标志
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            buffer_full <= 1'b0;
            buffer_empty <= 1'b1;
        end else begin
            // 缓存满判断
            if ((state == FILLING || state == REFILLING) && write_addr == BUFFER_DEPTH - 1 && input_handshake) begin
                buffer_full <= 1'b1;
            end else if (state == IDLE) begin
                buffer_full <= 1'b0;
            end else if (state == SENDING && next_state == REFILLING) begin
                buffer_full <= 1'b0;  // 即将进入REFILLING，提前清除满标志
            end
            
            // 缓存空判断
            if (state == IDLE) begin
                buffer_empty <= 1'b1;
            end else if (state == REFILLING && input_handshake) begin
                buffer_empty <= 1'b0;  // REFILLING开始读取时清除空标志
            end else if ((state == FILLING) && input_handshake) begin
                buffer_empty <= 1'b0;
            end else if (state == SENDING && read_addr == BUFFER_DEPTH - 1 && output_handshake) begin
                buffer_empty <= 1'b1;
            end
        end
    end
    
    // 缓存写入逻辑
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < BUFFER_DEPTH; i = i + 1) begin
                buffer_mem[i] <= {DATA_WIDTH{1'b0}};
            end
        end else if ((state == FILLING || state == REFILLING) && input_handshake) begin
            buffer_mem[write_addr] <= i_data_in;
        end
    end
    
    // 上游ready信号（组合逻辑，立即响应）
    always @(*) begin
        case (state)
            FILLING, REFILLING: begin
                if (buffer_full) begin
                    o_data_in_ready = 1'b0;  // 缓存满，停止接收
                end else begin
                    o_data_in_ready = 1'b1;  // 继续接收
                end
            end
            
            default: begin
                o_data_in_ready = 1'b0;
            end
        endcase
    end
    
    // 输出数据和valid信号
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_data_out <= {DATA_WIDTH{1'b0}};
            o_data_out_valid <= 1'b0;
        end else begin
            case (state)
                SENDING: begin
                    if (!buffer_empty) begin
                        // 握手完成后，立即更新到下一个数据
                        if (output_handshake) begin
                            if (read_addr == BUFFER_DEPTH - 1) begin
                                // 最后一个数据，下一周期valid拉低
                                o_data_out_valid <= 1'b0;
                            end else begin
                                // 输出下一个数据
                                o_data_out <= buffer_mem[read_addr + 1'b1];
                                o_data_out_valid <= 1'b1;
                            end
                        end else begin
                            // 保持当前数据
                            o_data_out <= buffer_mem[read_addr];
                            o_data_out_valid <= 1'b1;
                        end
                    end else begin
                        o_data_out_valid <= 1'b0;
                    end
                end
                
                default: begin
                    o_data_out_valid <= 1'b0;
                end
            endcase
        end
    end
    
    // 调试信息（仿真使用）
    `ifdef SIMULATION
    always @(posedge clk) begin
        if (state != next_state) begin
            $display("[%0t] Data_Buffer: State %0d -> %0d", $time, state, next_state);
        end
        if (state == FILLING && input_handshake) begin
            $display("[%0t] Data_Buffer: Write [%0d] = 0x%02h", $time, write_addr, i_data_in);
        end
        if (state == SENDING && output_handshake) begin
            $display("[%0t] Data_Buffer: Read [%0d] = 0x%02h", $time, read_addr, o_data_out);
        end
        if (buffer_full) begin
            $display("[%0t] Data_Buffer: Buffer FULL (%0d words)", $time, BUFFER_DEPTH);
        end
        if (ctrl_posedge) begin
            $display("[%0t] Data_Buffer: Control POSEDGE detected, state=%0d", $time, state);
        end
        if (ctrl_negedge) begin
            $display("[%0t] Data_Buffer: Control NEGEDGE - Reset", $time);
        end
        if (state == WAIT_TRIG) begin
            $display("[%0t] Data_Buffer: WAIT_TRIG state, ctrl_enable=%b, ctrl_enable_d1=%b, posedge=%b", 
                     $time, i_ctrl_enable, ctrl_enable_d1, ctrl_posedge);
        end
    end
    `endif

endmodule
