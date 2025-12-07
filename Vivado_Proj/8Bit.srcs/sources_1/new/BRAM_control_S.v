
`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: BM_control_stream_v2
// Description: BRAM controller with FIFO+MUX latency compensation
//              READY拉低后至少要等待三个cycle才能再次拉高READY 
//              阶段1(冷启动): 建立lead_ptr和actual_ptr的固定差值
//              阶段2(热运行): 
//                - 填充: 反压后FIFO重新填充到满
//                - 就绪: FIFO满,valid拉高
//                - 输出: MUX从FIFO切换到BRAM,双指针同步递增
//////////////////////////////////////////////////////////////////////////////////

module BM_control_stream_v2
#(
    parameter WIDTH = 8,            // BRAM data width
    parameter ADDR_RANGE = 128,     // Number of addresses to read
    parameter BRAM_LATENCY = 2,      // BRAM internal latency (cycles)
    parameter ADDR_BIT = $clog2(ADDR_RANGE)
)
(
    input clk,
    input rst_n,
    
    input en,
    // Status output
    output reg o_addr_done,
    
    // BRAM interface
    input [WIDTH-1:0] i_bram_data,
    output reg [ADDR_BIT-1:0] o_bram_addr,
    
    // Downstream interface
    output [WIDTH-1:0] o_data_out,
    output reg o_data_out_valid,
    input i_data_out_ready
);

    localparam FIFO_DEPTH = BRAM_LATENCY + 0; 
    

    localparam FIFO_CNT_FULL = BRAM_LATENCY;
    reg [$clog2(FIFO_CNT_FULL+1):0] fifo_counter; // fifo计数器,配合MUX
    reg [$clog2(FIFO_CNT_FULL+1):0] counter; // 计数器，指导冷启动
    reg [$clog2(ADDR_RANGE):0] actual_ptr; // 实际读指针 表示BRAM下次要握手到的数据
    reg [3:0] state, next_state, last_state;
    localparam setup = 0, fill_fifo = 1, idle = 2, read = 3;
    reg fire;//用于实现一拍保持的一个握手buffer
    always @(posedge clk)begin
        fire <= i_data_out_ready & o_data_out_valid;
    end
    //状态机
    always @(*)begin
        case(state)
            setup:begin
                next_state = en ? ( ((counter == BRAM_LATENCY -1) & i_data_out_ready) ? read : ((counter == BRAM_LATENCY) ? fill_fifo : setup)) : setup;
            end
            fill_fifo:begin
                next_state = (i_data_out_ready) ?  read : ((fifo_counter == FIFO_CNT_FULL) ? idle : fill_fifo);
                // next_state = ((fifo_counter == FIFO_CNT_FULL) ? idle : fill_fifo);
            end
            idle:begin
                next_state = (i_data_out_ready) ? read : idle;
            end
            read:begin
                next_state = (~i_data_out_ready) ? fill_fifo : read;
            end
        endcase
    end

    always @(posedge clk or negedge rst_n)begin
        if(~rst_n)begin
            state <= setup;
            last_state <= setup;
        end
        else begin
            state <= next_state;
            last_state <= state;
        end
    end


    integer i;
    // FIFO
    reg [WIDTH-1:0] fifo [0:FIFO_DEPTH-1];
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for(i=0;i<FIFO_DEPTH;i=i+1) begin
                fifo[i] <= {WIDTH{1'b0}};
            end
        end else if ((state == fill_fifo) | ((state == read) & (~fire))) begin
            if(fifo_counter != FIFO_DEPTH)begin
                fifo[0] <= i_bram_data;
                for(i=1;i<FIFO_DEPTH;i=i+1) begin
                    fifo[i] <= fifo[i-1];
                end
            end
        end 
    end
    //MUX
    assign o_data_out = (fifo_counter == 0) ? i_bram_data : fifo[fifo_counter-1];

    //FIFO计数器更新
    always @(posedge clk or negedge rst_n) begin
        if(~rst_n)begin
            fifo_counter<=0;
        end
        else if((state == fill_fifo) )begin
            if(last_state != read)begin
            fifo_counter <= (fifo_counter == FIFO_CNT_FULL) ? fifo_counter : (fifo_counter + 1);
            end
        end
        else if(state == read)begin
            fifo_counter <= (i_data_out_ready) ? ((fifo_counter > 0) ? (fifo_counter - 1) : 0) : 1;
        end
    end

    // 冷启动计数器更新
    always @(posedge clk or negedge rst_n) begin
        if(~rst_n)begin
            counter <= 0;
        end
        else if(state == setup && en)begin
            counter <= counter + 1;
        end
    end
    wire fire_w = i_data_out_ready & o_data_out_valid;
    //o_bram_addr 和 actual_ptr逻辑
    always @(posedge clk or negedge rst_n)begin
        if(~rst_n)begin
            o_bram_addr <= 0;
        end
        else if(state == setup & (o_bram_addr < BRAM_LATENCY) & en)begin
            o_bram_addr <= o_bram_addr + 1;
        end
        else if((state == idle & i_data_out_ready) | (((state == read) | (state == fill_fifo) )& i_data_out_ready))begin
                o_bram_addr <= (o_bram_addr + 1) ;
        end
        // else if(state == fill_fifo)begin
        //     o_bram_addr <= (last_state == read) ? actual_ptr + 3 : actual_ptr + 2;
        // end
    end
    always @(posedge clk or negedge rst_n) begin
        if(~rst_n)begin
            actual_ptr <= 0;
        end
        else if((state == read &((last_state == idle) | fire |(last_state == fill_fifo))) | (state == read & fire_w) )begin
                actual_ptr <= actual_ptr + 1;
        end
    end

    //valid 逻辑
    always @(posedge clk or negedge rst_n) begin
        if(~rst_n)begin
            o_data_out_valid <= 0;
        end
        else if(state == idle)begin
            o_data_out_valid <= 1;
        end
        else if(state == read)begin
            o_data_out_valid <= (1);
        end
        else if((state == fill_fifo))begin
            o_data_out_valid <= 1;
        end
        else begin
            o_data_out_valid <= 0;
        end
    end
    //o_addr_done 逻辑
    always @(posedge clk or negedge rst_n) begin
        if(~rst_n)begin
            o_addr_done <= 0;
        end
        else if(actual_ptr == ADDR_RANGE)begin
            o_addr_done <= 1;
        end
        else begin
            o_addr_done <= 0;
        end
    end

endmodule



module BM_control_stream_v2_V //这个模块是默先拉高valid的时序
#(
    parameter WIDTH = 8,            // BRAM data width
    parameter ADDR_RANGE = 128,     // Number of addresses to read
    parameter BRAM_LATENCY = 2      // BRAM internal latency (cycles)
)
(
    input clk,
    input rst_n,
    
    input en,
    // Status output
    output reg o_addr_done,
    
    // BRAM interface
    input [WIDTH-1:0] i_bram_data,
    output reg [ADDR_BIT-1:0] o_bram_addr,
    
    // Downstream interface
    output [WIDTH-1:0] o_data_out,
    output reg o_data_out_valid,
    input i_data_out_ready
);

    localparam ADDR_BIT = $clog2(ADDR_RANGE);
    localparam FIFO_DEPTH = BRAM_LATENCY + 0; 
    

    localparam FIFO_CNT_FULL = BRAM_LATENCY;
    reg [$clog2(FIFO_CNT_FULL+1):0] fifo_counter; // fifo计数器,配合MUX
    reg [$clog2(FIFO_CNT_FULL+1):0] counter; // 计数器，指导冷启动
    reg [$clog2(ADDR_RANGE):0] actual_ptr; // 实际读指针 表示BRAM下次要握手到的数据
    reg [3:0] state, next_state, last_state;
    localparam setup = 0, fill_fifo = 1, idle = 2, read = 3;
    reg fire;//用于实现一拍保持的一个握手buffer
    wire w_fire;
    assign w_fire = i_data_out_ready & o_data_out_valid;
    always @(posedge clk)begin
        fire <= i_data_out_ready & o_data_out_valid;
    end
    //状态机
    always @(*)begin
        case(state)
            setup:begin
                next_state = en ? ((counter == BRAM_LATENCY) ? fill_fifo : setup) : setup;
            end
            fill_fifo:begin
                next_state = (i_data_out_ready) ?  read : ((fifo_counter == FIFO_CNT_FULL) ? idle : fill_fifo);
            end
            idle:begin
                next_state = (i_data_out_ready) ? read : idle;
            end
            read:begin
                next_state = (~i_data_out_ready) ? fill_fifo : read;
            end
        endcase
    end

    always @(posedge clk or negedge rst_n)begin
        if(~rst_n)begin
            state <= setup;
            last_state <= setup;
        end
        else begin
            state <= next_state;
            last_state <= state;
        end
    end


    integer i;
    // FIFO
    reg [WIDTH-1:0] fifo [0:FIFO_DEPTH-1];
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for(i=0;i<FIFO_DEPTH;i=i+1) begin
                fifo[i] <= {WIDTH{1'b0}};
            end
        end else if ((state == fill_fifo) | ((state == read) & (~fire)&(~w_fire))) begin
            if(fifo_counter != FIFO_DEPTH)begin
                fifo[0] <= i_bram_data;
                for(i=1;i<FIFO_DEPTH;i=i+1) begin
                    fifo[i] <= fifo[i-1];
                end
            end
        end 
    end
    //MUX
    assign o_data_out = (fifo_counter == 0) ? i_bram_data : fifo[fifo_counter-1];

    //FIFO计数器更新
    always @(posedge clk or negedge rst_n) begin
        if(~rst_n)begin
            fifo_counter<=0;
        end
        else if((state == fill_fifo) )begin
            if(last_state != read)begin
            fifo_counter <= (fifo_counter == FIFO_CNT_FULL) ? fifo_counter : (fifo_counter + 1);
            end
        end
        else if(state == read)begin
            fifo_counter <= (i_data_out_ready) ? ((fifo_counter > 0) ? (fifo_counter - 1) : 0) : 1;
        end
    end

    // 冷启动计数器更新
    always @(posedge clk or negedge rst_n) begin
        if(~rst_n)begin
            counter <= 0;
        end
        else if(state == setup && en)begin
            counter <= counter + 1;
        end
    end

    //o_bram_addr 和 actual_ptr逻辑
    always @(posedge clk or negedge rst_n)begin
        if(~rst_n)begin
            o_bram_addr <= 0;
        end
        else if(state == setup & (o_bram_addr < BRAM_LATENCY) & en)begin
            o_bram_addr <= o_bram_addr + 1;
        end
        else if((state == idle & i_data_out_ready) | (((state == read) | (state == fill_fifo) )& i_data_out_ready))begin
                o_bram_addr <= (o_bram_addr + 1) ;
        end
        // else if(state == fill_fifo)begin
        //     o_bram_addr <= (last_state == read) ? actual_ptr + 3 : actual_ptr + 2;
        // end
    end
    always @(posedge clk or negedge rst_n) begin
        if(~rst_n)begin
            actual_ptr <= 0;
        end
        else if((state == read &((last_state == idle) | fire | w_fire |(last_state == fill_fifo))) )begin
                actual_ptr <= actual_ptr + 1;
        end
    end

    //valid 逻辑
    always @(posedge clk or negedge rst_n) begin
        if(~rst_n)begin
            o_data_out_valid <= 0;
        end
        else if(state == idle)begin
            o_data_out_valid <= 1;
        end
        else if(state == read)begin
            o_data_out_valid <= (1);
        end
        else if((state == fill_fifo))begin
            o_data_out_valid <= 1;
        end
        else begin
            o_data_out_valid <= 0;
        end
    end
    //o_addr_done 逻辑
    always @(posedge clk or negedge rst_n) begin
        if(~rst_n)begin
            o_addr_done <= 0;
        end
        else if(actual_ptr == ADDR_RANGE)begin
            o_addr_done <= 1;
        end
        else begin
            o_addr_done <= 0;
        end
    end

endmodule