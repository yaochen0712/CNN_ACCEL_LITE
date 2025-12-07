`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: Cache
// Description: 并行转串行缓存模块，支持门控
//              - 输入：CHANNEL个并行数据
//              - 输出：串行输出有效数据（从低到高）
//              - gate_en：控制有效通道数量（低位优先）
//              - 工作流程：
//                1. IDLE状态：等待并行数据输入
//                2. FULL状态：数据已存储，等待下游就绪
//                3. READ状态：串行输出数据，从低到高
//////////////////////////////////////////////////////////////////////////////////

module Cache 
#(
    parameter D_WIDTH = 8,          // 数据位宽
    parameter CHANNEL = 128,        // 最大通道数
    parameter GATE_PARA = 4         // 门控参数位宽 (2^GATE_PARA组)
)
(
    input wire clk,
    input wire rst_n,

    // 配置接口
    input wire [$clog2(GATE_PARA):0] i_cfg_gate_en,     // 门控使能配置
    input wire i_cfg_valid,                        // 配置有效信号
    
    // 上游并行数据接口
    input wire [D_WIDTH*CHANNEL-1:0] i_data_parallel,
    input wire i_data_parallel_valid,
    output reg o_data_parallel_ready,

    // 下游串行数据接口
    output wire [D_WIDTH-1:0] o_data_serial,
    output reg o_data_serial_valid,
    input wire i_data_serial_ready,

    // 状态输出
    output reg o_mem_full,
    output reg o_mem_empty
);

    // ========== 内部信号 ==========
    localparam CNT_WIDTH = $clog2(CHANNEL);
    
    reg [CNT_WIDTH:0] count_max;          // 最大计数值（有效通道数）
    reg [CNT_WIDTH:0] counter;            // 当前输出计数器
    reg [$clog2(GATE_PARA):0] gate_en_reg;        // 门控配置寄存器
    reg [D_WIDTH*CHANNEL-1:0] mem_array;    // 数据存储器

    // 状态机
    reg [2:0] state, next_state;
    localparam IDLE = 3'b000,
               FULL = 3'b001,
               READ = 3'b010;

    // 握手信号
    wire input_handshake  = i_data_parallel_valid && o_data_parallel_ready;
    wire output_handshake = o_data_serial_valid && i_data_serial_ready;

    // ========== 配置更新逻辑 ==========
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gate_en_reg <= {($clog2(GATE_PARA)+1){1'b0}};
        end else if (i_cfg_valid) begin
            gate_en_reg <= i_cfg_gate_en;
        end
    end

    // COUNT_MAX计算：根据gate_en确定有效通道数
    // gate_en表示有效的分组数，每组有(CHANNEL / 2^GATE_PARA)个通道
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count_max <= CHANNEL - 1;
        end else if (i_cfg_valid) begin
            // 计算有效通道数 = (CHANNEL / 2^GATE_PARA) * (gate_en + 1) - 1
            // 简化：右移GATE_PARA位，然后左移gate_en位
            count_max <= ((CHANNEL >> GATE_PARA) << (GATE_PARA - i_cfg_gate_en)) - 1;
        end
    end

    // ========== 状态机 - 次态逻辑 ==========
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end

    // ========== 状态机 - 转移逻辑 ==========
    always @(*) begin
        next_state = state;  // 默认保持
        case (state)
            IDLE: begin 
                if (input_handshake) begin
                    next_state = FULL;
                end
            end
            
            FULL: begin
                if (i_data_serial_ready) begin
                    next_state = READ;
                end
            end
            
            READ: begin
                if (output_handshake && (counter == 0)) begin
                    next_state = IDLE;
                end else if (!i_data_serial_ready) begin
                    next_state = FULL;
                end
            end
            
            default: next_state = IDLE;
        endcase
    end

    // ========== 上游Ready信号控制 ==========
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_data_parallel_ready <= 1'b1 ;  // 上电默认就绪
        end else begin
            case (state)
                IDLE: begin 
                    o_data_parallel_ready <= 1'b1 & (~input_handshake);  // 空闲时就绪
                end
                FULL, READ: begin
                    o_data_parallel_ready <= 1'b0;  // 满或读取时不就绪
                end
                default: o_data_parallel_ready <= 1'b0;
            endcase
        end 
    end

    // ========== 下游Valid信号控制 ==========
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_data_serial_valid <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    o_data_serial_valid <= 1'b0;
                end
                FULL: begin
                    o_data_serial_valid <= 1'b1;  // 满时拉高valid
                end
                READ: begin
                    if (output_handshake && (counter == 0)) begin
                        o_data_serial_valid <= 1'b0;  // 最后一个数据发出后拉低
                    end else begin
                        o_data_serial_valid <= 1'b1;  // 读取过程中保持valid
                    end
                end
                default: o_data_serial_valid <= 1'b0;
            endcase
        end 
    end
    reg [CNT_WIDTH:0] counter_mvalue;
    // ========== 计数器更新逻辑 ==========
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter <= {CNT_WIDTH{1'b0}};
            counter_mvalue <= {CNT_WIDTH{1'b0}};
        end else begin
            if (input_handshake) begin
                // 输入握手成功，加载最大计数值
                counter <= count_max;
                counter_mvalue <= count_max;
            end else if (output_handshake && (counter != 0)) begin
                // 输出握手成功且未到0，递减
                counter <= counter - 1'b1;
            end
        end
    end

    // ========== 数据存储器 ==========
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_array <= {(D_WIDTH*CHANNEL){1'b0}};
        end else if (input_handshake) begin
            mem_array <= i_data_parallel;
        end
    end

    // ========== 串行数据输出 ==========
    // 从低位通道开始输出 (counter从count_max递减到0)
    assign o_data_serial = mem_array[D_WIDTH*(counter_mvalue-counter) +: D_WIDTH];

    // ========== 状态标志 ==========
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_mem_full  <= 1'b0;
            o_mem_empty <= 1'b1;
        end else begin
            case (state)
                IDLE: begin
                    o_mem_full  <= 1'b0 | input_handshake;
                    o_mem_empty <= 1'b1 & (~input_handshake);
                end
                FULL, READ: begin
                    o_mem_full  <= 1'b1;
                    o_mem_empty <= 1'b0;
                end
                default: begin
                    o_mem_full  <= 1'b0;
                    o_mem_empty <= 1'b1;
                end
            endcase
        end
    end

endmodule