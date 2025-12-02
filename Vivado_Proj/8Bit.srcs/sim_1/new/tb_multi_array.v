`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: tb_multi_array
// Description: Independent channel streaming testbench
//              - 每个通道独立的valid-ready握手
//              - 支持异步到达和流式传输
//////////////////////////////////////////////////////////////////////////////////

module tb_multi_array();

    parameter CHANNEL_NUM = 4;
    parameter DATA_WIDTH = 8;
    parameter DOUT_WIDTH = 16;
    parameter LATENCY = 3;
    parameter GATE_PARA = 2;
    parameter CLK_PERIOD = 10;

    reg clk;
    reg rst_n;

    wire r_error;
    wire r_bram_data_ready;
    reg [CHANNEL_NUM*DATA_WIDTH-1:0] w_bram_data_din;
    reg w_bram_data_valid;
    
    wire r_bram_weight_ready;
    reg [CHANNEL_NUM*DATA_WIDTH-1:0] w_bram_weight_din;
    reg w_bram_weight_valid;
    
    wire [CHANNEL_NUM*DOUT_WIDTH-1:0] r_data_out;
    wire r_data_out_valid;
    reg w_data_out_ready;
    
    reg w_i_cfg_valid;
    reg [$clog2(GATE_PARA)-1:0] w_i_gate_en;

    // 测试统计
    integer output_count = 0;

    // DUT实例化
    multi_array #(
        .NUM_MULTS(CHANNEL_NUM),
        .DIN_WIDTH(DATA_WIDTH),
        .WGT_WIDTH(DATA_WIDTH),
        .DOUT_WIDTH(DOUT_WIDTH),
        .LATENCY(LATENCY),
        .GATE_PARA(GATE_PARA)
    )
    uut0(
        .clk(clk),
        .rst_n(rst_n),
        .o_error(r_error),
        .i_bram_data_din(w_bram_data_din),
        .i_bram_data_valid(w_bram_data_valid),
        .o_bram_data_ready(r_bram_data_ready),
        .i_bram_weight_din(w_bram_weight_din),
        .i_bram_weight_valid(w_bram_weight_valid),
        .o_bram_weight_ready(r_bram_weight_ready),
        .o_data_out(r_data_out),
        .o_data_out_valid(r_data_out_valid),
        .i_data_out_ready(w_data_out_ready),
        .i_cfg_valid(w_i_cfg_valid),
        .i_gate_en(w_i_gate_en)
    );

    // 时钟生成
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // 握手检测
    wire data_handshake = w_bram_data_valid && r_bram_data_ready;
    wire weight_handshake = w_bram_weight_valid && r_bram_weight_ready;
    wire output_handshake = r_data_out_valid && w_data_out_ready;

    // 监控输出
    always @(posedge clk) begin
        if (output_handshake) begin
            output_count = output_count + 1;
            $display("[%0t] Output #%0d: data_out = %h", $time, output_count, r_data_out);
        end
        if (r_error) begin
            $display("[%0t] ERROR detected!", $time);
        end
    end

    // ========== Task: 复位 ==========
    task reset_dut;
        begin
            $display("\n[%0t] ========== Reset Start ==========", $time);
            rst_n = 0;
            w_bram_data_din = 0;
            w_bram_data_valid = 0;
            w_bram_weight_din = 0;
            w_bram_weight_valid = 0;
            w_data_out_ready = 1;
            w_i_cfg_valid = 0;
            w_i_gate_en = 2'b01;
            output_count = 0;
            
            repeat(5) @(posedge clk);
            rst_n = 1;
            repeat(3) @(posedge clk);
            $display("[%0t] ========== Reset Complete ==========\n", $time);
        end
    endtask

    // ========== Task: 配置门控 ==========
    task config_gating;
        input [$clog2(GATE_PARA)-1:0] gate_en;
        begin
            @(posedge clk);
            w_i_gate_en = gate_en;
            w_i_cfg_valid = 1;
            @(posedge clk);
            w_i_cfg_valid = 0;
            $display("[%0t] Gating configured: %b", $time, gate_en);
        end
    endtask

    // ========== Task: 流式独立通道传输 ==========
    // 参数说明：
    //   num_transactions: 每个通道传输多少个数据
    //   data_base: 数据初始值
    //   weight_base: 权重初始值
    //   data_init_delay: 数据通道初始延迟（周期数）
    //   weight_init_delay: 权重通道初始延迟（周期数）
    //   data_between_delay: 数据握手间的延迟（0=连续）
    //   weight_between_delay: 权重握手间的延迟（0=连续）
    
    task automatic stream_independent_channels;
        input integer num_transactions;
        input [CHANNEL_NUM*DATA_WIDTH-1:0] data_base;
        input [CHANNEL_NUM*DATA_WIDTH-1:0] weight_base;
        input integer data_init_delay;
        input integer weight_init_delay;
        input integer data_between_delay;
        input integer weight_between_delay;
        
        integer trans_idx;
        integer data_trans_count;
        integer weight_trans_count;
        
        reg [CHANNEL_NUM*DATA_WIDTH-1:0] current_data;
        reg [CHANNEL_NUM*DATA_WIDTH-1:0] current_weight;
        
        begin
            $display("\n[%0t] ========== Independent Channel Streaming Start ==========", $time);
            $display("  Num Transactions: %0d per channel", num_transactions);
            $display("  Data Base: %h, Weight Base: %h", data_base, weight_base);
            $display("  Data Init Delay: %0d, Between Delay: %0d", data_init_delay, data_between_delay);
            $display("  Weight Init Delay: %0d, Between Delay: %0d", weight_init_delay, weight_between_delay);
            
            data_trans_count = 0;
            weight_trans_count = 0;
            w_bram_data_valid = 0;
            w_bram_weight_valid = 0;
            w_bram_data_din = 0;
            w_bram_weight_din = 0;
            
            fork
                // ===== 数据通道 =====
                begin
                    repeat(data_init_delay) @(posedge clk);
                    
                    for (trans_idx = 0; trans_idx < num_transactions; trans_idx = trans_idx + 1) begin
                        current_data = data_base + trans_idx;
                        w_bram_data_din = current_data;
                        w_bram_data_valid = 1;
                        
                        @(posedge clk);
                        
                        while (!data_handshake) begin
                            @(posedge clk);
                        end
                        
                        data_trans_count = data_trans_count + 1;
                        $display("[%0t] Data Handshake #%0d: %h", $time, data_trans_count, current_data);
                        
                        w_bram_data_valid = 0;
                        w_bram_data_din = 0;
                        
                        repeat(data_between_delay) @(posedge clk);
                    end
                end
                
                // ===== 权重通道 =====
                begin
                    repeat(weight_init_delay) @(posedge clk);
                    
                    for (trans_idx = 0; trans_idx < num_transactions; trans_idx = trans_idx + 1) begin
                        current_weight = weight_base + trans_idx;
                        w_bram_weight_din = current_weight;
                        w_bram_weight_valid = 1;
                        
                        @(posedge clk);
                        
                        while (!weight_handshake) begin
                            @(posedge clk);
                        end
                        
                        weight_trans_count = weight_trans_count + 1;
                        $display("[%0t] Weight Handshake #%0d: %h", $time, weight_trans_count, current_weight);
                        
                        w_bram_weight_valid = 0;
                        w_bram_weight_din = 0;
                        
                        repeat(weight_between_delay) @(posedge clk);
                    end
                end
            join
            
            $display("[%0t] ========== Independent Streaming Complete ==========", $time);
            $display("  Data: %0d, Weight: %0d transactions\n", data_trans_count, weight_trans_count);
        end
    endtask

    // ========== 主测试流程 ==========
    initial begin
        $display("\n");
        $display("========================================");
        $display("  Independent Channel Streaming");
        $display("  Real-World Async Scenario");
        $display("========================================");

        // ===== Test Case 1: 同时到达，连续传输 =====
        $display("\n[Test Case 1] Simultaneous Arrival, Continuous Streaming");
        reset_dut();
        config_gating(1);
        w_data_out_ready = 1;
        
        stream_independent_channels(
            20,                                   // 20个数据
            {8'd10, 8'd9, 8'd8, 8'd7},           // 数据初值
            {8'd20, 8'd19, 8'd18, 8'd17},        // 权重初值
            0, 7,                                 // 无初始延迟
            0, 0                                  // 无握手间延迟
        );
        
        repeat(20) @(posedge clk);

        // ===== Test Case 2: 数据先到达，权重延迟 =====
        $display("\n[Test Case 2] Data Arrives First, Weight Delayed");
        reset_dut();
        config_gating(GATE_PARA);
        w_data_out_ready = 1;
        
        stream_independent_channels(
            15,                                   // 15个数据
            {8'd30, 8'd29, 8'd28, 8'd27},        // 数据初值
            {8'd40, 8'd39, 8'd38, 8'd37},        // 权重初值
            0, 8,                                 // 数据立即，权重延迟8个周期
            0, 1                                  // 数据连续，权重间隔1周期
        );
        
        repeat(20) @(posedge clk);

        // ===== Test Case 3: 权重先到达，数据延迟 =====
        $display("\n[Test Case 3] Weight Arrives First, Data Delayed");
        reset_dut();
        config_gating(2'b00);
        w_data_out_ready = 1;
        
        stream_independent_channels(
            15,                                   // 15个数据
            {8'd50, 8'd49, 8'd48, 8'd47},        // 数据初值
            {8'd60, 8'd59, 8'd58, 8'd57},        // 权重初值
            5, 0,                                 // 数据延迟5周期，权重立即
            2, 0                                  // 数据间隔2周期，权重连续
        );
        
        repeat(20) @(posedge clk);

        // ===== Test Case 4: 两路都有延迟和间隔 - 压力测试 =====
        $display("\n[Test Case 4] Both Channels with Delays - Pressure Test");
        reset_dut();
        config_gating(GATE_PARA);
        w_data_out_ready = 1;
        
        stream_independent_channels(
            25,                                   // 25个数据
            {8'd100, 8'd99, 8'd98, 8'd97},      // 数据初值
            {8'd110, 8'd109, 8'd108, 8'd107},  // 权重初值
            3, 7,                                 // 数据延迟3周期，权重延迟7周期
            1, 2                                  // 数据间隔1周期，权重间隔2周期
        );
        
        repeat(30) @(posedge clk);

        // ===== 测试结束 =====
        $display("\n========================================");
        $display("  All Tests Completed Successfully");
        $display("  Total Outputs Received: %0d", output_count);
        $display("========================================\n");
        
        repeat(10) @(posedge clk);
        $finish;
    end

    // 超时保护
    initial begin
        #500000;
        $display("[%0t] ERROR: Simulation Timeout!", $time);
        $finish;
    end

endmodule