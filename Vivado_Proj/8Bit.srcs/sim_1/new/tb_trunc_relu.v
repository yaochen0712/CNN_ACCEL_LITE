`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: tb_trunc_relu
// Description: Testbench for ReLU + Truncation cascade with handshake protocol
//              测试流程: Input -> ReLU -> Truncation -> Output
//              - 完整的valid-ready握手
//              - 配置测试（截位起始位、饱和使能）
//              - 背压测试
//              - 边界条件测试
//              - 自动结果检查和错误统计
//////////////////////////////////////////////////////////////////////////////////

module tb_trunc_relu();

    // ========== 参数定义 ==========
    parameter DATA_WIDTH = 16;      // ReLU输入/输出宽度
    parameter TRUNC_WIDTH = 8;      // Truncation输出宽度
    parameter CLK_PERIOD = 10;      // 10ns时钟周期
    parameter PIPELINE = 0;         // ReLU是否使用流水线

    // ========== 时钟和复位 ==========
    reg clk;
    reg rst_n;

    // =========== 配置Relu ==========
    reg cfg_en,relu_en;
    // ========== 测试输入 ==========
    reg signed [DATA_WIDTH-1:0] stimulus_data;
    reg stimulus_valid;
    wire stimulus_ready;

    // ========== ReLU -> Truncation 连接 ==========
    wire signed [DATA_WIDTH-1:0] relu_out;
    wire relu_out_valid;
    wire relu_out_ready;

    // ========== Truncation配置 ==========
    reg [$clog2(DATA_WIDTH)-1:0] trunc_lsb_idx;
    reg trunc_saturate_en;
    reg trunc_cfg_en;

    // ========== 最终输出 ==========
    wire [TRUNC_WIDTH-1:0] final_out;
    wire final_out_valid;
    reg final_out_ready;

    // ========== 测试控制 ==========
    integer test_case;
    integer data_sent;
    integer data_received;
    integer errors;
    integer passed;

    // ========== 预期值计算 ==========
    reg [DATA_WIDTH-1:0] expected_relu;
    reg [TRUNC_WIDTH-1:0] expected_trunc;
    reg [DATA_WIDTH-1:0] shifted_value;
    reg has_overflow;
    
    // 预期值队列（用于流水线延迟）
    reg [TRUNC_WIDTH-1:0] expected_queue [0:15];
    reg [DATA_WIDTH-1:0] input_queue [0:15];
    integer queue_wr_ptr;
    integer queue_rd_ptr;
    integer queue_count;

    // ========== DUT实例化 ==========
    
    // ReLU模块
    ReLU #(
        .DATA_WIDTH(DATA_WIDTH),
        .PIPELINE(PIPELINE)
    ) u_relu (
        .clk(clk),
        .rst_n(rst_n),
        .i_data_in(stimulus_data),
        .i_data_in_valid(stimulus_valid),
        .i_data_in_ready(stimulus_ready),
        .o_data_out(relu_out),
        .o_data_out_valid(relu_out_valid),
        .o_data_out_ready(relu_out_ready),
        .i_cfg_en(cfg_en),
        .i_relu_cfg(relu_en)
    );

    // Truncation模块
    trunction #(
        .DIN_WIDTH(DATA_WIDTH),
        .DOUT_WIDTH(TRUNC_WIDTH)
    ) u_trunc (
        .clk(clk),
        .rst_n(rst_n),
        .i_din(relu_out),
        .i_din_valid(relu_out_valid),
        .o_din_ready(relu_out_ready),
        .o_dout(final_out),
        .o_dout_valid(final_out_valid),
        .i_dout_ready(final_out_ready),
        .i_trunction_cfg_lsb_idx(trunc_lsb_idx),
        .i_trunction_cfg_saturate_en(trunc_saturate_en),
        .i_trunction_cfg_en(trunc_cfg_en)
    );

    // ========== 时钟生成 ==========
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ========== 握手检测 ==========
    wire input_handshake = stimulus_valid && stimulus_ready;
    wire relu_handshake = relu_out_valid && relu_out_ready;
    wire output_handshake = final_out_valid && final_out_ready;

    // ========== 预期值计算函数 ==========
    function [TRUNC_WIDTH-1:0] calc_expected;
        input signed [DATA_WIDTH-1:0] data_in;
        input [$clog2(DATA_WIDTH)-1:0] lsb_idx;
        input saturate;
        reg signed [DATA_WIDTH-1:0] relu_result;
        reg [DATA_WIDTH-1:0] shifted;
        reg overflow;
        integer i;
        begin
            // 步骤1: ReLU
            if (data_in[DATA_WIDTH-1] == 1'b1) begin
                relu_result = {DATA_WIDTH{1'b0}};  // 负数输出0
            end else begin
                relu_result = data_in;              // 正数保持
            end
            
            // 步骤2: 右移
            shifted = relu_result >> lsb_idx;
            
            // 步骤3: 检测溢出
            overflow = 1'b0;
            for (i = TRUNC_WIDTH; i < DATA_WIDTH; i = i + 1) begin
                if (shifted[i] == 1'b1) begin
                    overflow = 1'b1;
                end
            end
            
            // 步骤4: 截位或饱和
            if (saturate && overflow) begin
                calc_expected = {TRUNC_WIDTH{1'b1}};  // 饱和到最大值
            end else begin
                calc_expected = shifted[TRUNC_WIDTH-1:0];  // 正常截位
            end
        end
    endfunction

    // ========== 预期值队列管理 ==========
    initial begin
        queue_wr_ptr = 0;
        queue_rd_ptr = 0;
        queue_count = 0;
    end

    // 输入握手时将预期值入队
    always @(posedge clk) begin
        if (input_handshake) begin
            expected_queue[queue_wr_ptr] = calc_expected(stimulus_data, trunc_lsb_idx, trunc_saturate_en);
            input_queue[queue_wr_ptr] = stimulus_data;
            queue_wr_ptr = (queue_wr_ptr + 1) % 16;
            queue_count = queue_count + 1;
        end
    end

    // ========== 结果检查 ==========
    always @(posedge clk) begin
        if (output_handshake && queue_count > 0) begin
            expected_trunc = expected_queue[queue_rd_ptr];
            
            if (final_out === expected_trunc) begin
                $display("[%0t] ✓ PASS: Input=0x%h, Output=0x%h, Expected=0x%h", 
                         $time, input_queue[queue_rd_ptr], final_out, expected_trunc);
                passed = passed + 1;
            end else begin
                $display("[%0t] ✗ FAIL: Input=0x%h, Output=0x%h, Expected=0x%h [lsb_idx=%0d, saturate=%b]", 
                         $time, input_queue[queue_rd_ptr], final_out, expected_trunc, 
                         trunc_lsb_idx, trunc_saturate_en);
                errors = errors + 1;
            end
            
            queue_rd_ptr = (queue_rd_ptr + 1) % 16;
            queue_count = queue_count - 1;
            data_received = data_received + 1;
        end
    end

    // ========== 握手监控 ==========
    always @(posedge clk) begin
        if (input_handshake) begin
            $display("[%0t] Input Handshake:  data=%0d (0x%h)", 
                     $time, $signed(stimulus_data), stimulus_data);
        end
        if (relu_handshake) begin
            $display("[%0t] ReLU Handshake:  relu_out=%0d (0x%h)", 
                     $time, $signed(relu_out), relu_out);
        end
    end

    // ========== Task: 复位 ==========
    task reset_dut;
        begin
            $display("\n[%0t] ========== Reset Start ==========", $time);
            rst_n = 0;
            stimulus_data = 0;
            stimulus_valid = 0;
            final_out_ready = 0;
            trunc_lsb_idx = 0;
            trunc_saturate_en = 0;
            trunc_cfg_en = 0;
            data_sent = 0;
            data_received = 0;
            errors = 0;
            passed = 0;
            queue_wr_ptr = 0;
            queue_rd_ptr = 0;
            queue_count = 0;
            
            repeat(5) @(posedge clk);
            rst_n = 1;
            repeat(2) @(posedge clk);
            $display("[%0t] ========== Reset Done ==========", $time);
        end
    endtask

    // ========== Task: 配置Truncation ==========
    task config_truncation;
        input [$clog2(DATA_WIDTH)-1:0] lsb_idx;
        input saturate;
        begin
            $display("\n[%0t] Config Truncation: lsb_idx=%0d, saturate=%b", 
                     $time, lsb_idx, saturate);
            @(posedge clk);
            trunc_cfg_en = 1;
            trunc_lsb_idx = lsb_idx;
            trunc_saturate_en = saturate;
            @(posedge clk);
            trunc_cfg_en = 0;
            @(posedge clk);
        end
    endtask

    // =========== Task:配置Relu =============
    task config_en_relu;
        begin
            @(posedge clk);
            cfg_en = 1;
            relu_en = 1;
            @(posedge clk);
            relu_en = 1;
            cfg_en = 0;
        end
    endtask
    // =========== Task:关闭Relu =============
    task config_disable_relu;
        begin
            @(posedge clk);
            cfg_en = 1;
            relu_en = 0;
            @(posedge clk);
            relu_en = 0;
            cfg_en = 0;
        end
    endtask


    // ========== Task: 发送单个数据 ==========
    task send_data;
        input signed [DATA_WIDTH-1:0] data;
        input wait_rand;
        integer wait_cycles;
        begin
            // 随机等待
            if (wait_rand) begin
                wait_cycles = ($random & 32'h7FFFFFFF) % 3;
                repeat(wait_cycles) @(posedge clk);
            end
            
            // 发送数据
            @(posedge clk);
            stimulus_data = data;
            stimulus_valid = 1;
            
            // 等待握手
            @(posedge clk);
            while (!input_handshake) begin
                @(posedge clk);
            end
            
            data_sent = data_sent + 1;
            
            // 握手成功后拉低valid
            @(posedge clk);
            stimulus_valid = 0;
        end
    endtask

    // ========== Task: 接收数据（带背压） ==========
    task receive_data;
        input enable_backpressure;
        input integer num_cycles;
        integer i;
        begin
            if (enable_backpressure) begin
                // 随机背压
                for (i = 0; i < num_cycles; i = i + 1) begin
                    @(posedge clk);
                    final_out_ready <= ($random & 1);
                end
            end else begin
                // 持续就绪
                final_out_ready = 1;
            end
        end
    endtask

    // ========== Task: 等待所有数据处理完成 ==========
    task wait_all_data;
        integer timeout;
        begin
            timeout = 0;
            while (queue_count > 0 && timeout < 100) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (timeout >= 100) begin
                $display("[%0t] WARNING: Timeout waiting for data, %0d items still in queue", 
                         $time, queue_count);
            end
        end
    endtask

    // ========== 主测试流程 ==========
    initial begin
        $display("========================================");
        $display("  ReLU + Truncation Testbench Start");
        $display("========================================");
        
        // ========== Test Case 0: 复位测试 ==========
        test_case = 0;
        $display("\n[Test Case %0d] Reset Test", test_case);
        reset_dut();
        config_en_relu();

        // ========== Test Case 1: 基本功能测试 ==========
        test_case = 1;
        $display("\n[Test Case %0d] Basic Function Test", test_case);
        $display("Config: lsb_idx=0, saturate=0 (直接截取低8位)");
        config_truncation(0, 0);
        final_out_ready = 1;
        
        // 正数测试
        send_data(16'h0123, 0);  // 正数 -> ReLU保持 -> 截取0x23
        send_data(16'h00FF, 0);  // 正数 -> ReLU保持 -> 截取0xFF
        
        // 负数测试
        send_data(-16'd100, 0);  // 负数 -> ReLU输出0 -> 截取0x00
        send_data(-16'd1, 0);    // 负数 -> ReLU输出0 -> 截取0x00
        
        wait_all_data();
        repeat(10) @(posedge clk);

        // ========== Test Case 2: LSB偏移测试 ==========
        test_case = 2;
        $display("\n[Test Case %0d] LSB Offset Test", test_case);
        $display("Config: lsb_idx=4, saturate=0 (从bit4开始截取)");
        config_truncation(4, 0);
        final_out_ready = 1;
        
        send_data(16'h1234, 0);  // 0x1234 >> 4 = 0x123, 截取0x23
        send_data(16'h0ABC, 0);  // 0x0ABC >> 4 = 0x0AB, 截取0xAB
        send_data(-16'd256, 0);  // 负数 -> 0, 截取0x00
        
        wait_all_data();
        repeat(10) @(posedge clk);

        // ========== Test Case 3: 饱和测试 ==========
        test_case = 3;
        $display("\n[Test Case %0d] Saturation Test", test_case);
        $display("Config: lsb_idx=0, saturate=1 (溢出时饱和到0xFF)");
        config_truncation(0, 1);
        final_out_ready = 1;
        
        send_data(16'h01FF, 0);  // 0x01FF > 8bit, 饱和到0xFF
        send_data(16'h0FFF, 0);  // 0x0FFF > 8bit, 饱和到0xFF
        send_data(16'h00AA, 0);  // 0x00AA < 8bit, 输出0xAA
        send_data(-16'd1000, 0); // 负数 -> 0, 输出0x00
        
        wait_all_data();
        repeat(10) @(posedge clk);

        // ========== Test Case 4: LSB偏移+饱和组合测试 ==========
        test_case = 4;
        $display("\n[Test Case %0d] LSB Offset + Saturation Test", test_case);
        $display("Config: lsb_idx=2, saturate=1");
        config_truncation(2, 1);
        final_out_ready = 1;
        
        send_data(16'h03FC, 0);  // 0x03FC >> 2 = 0x0FF, 截取0xFF
        send_data(16'h0FFC, 0);  // 0x0FFC >> 2 = 0x3FF, 溢出->0xFF
        send_data(16'h0004, 0);  // 0x0004 >> 2 = 0x001, 截取0x01
        
        wait_all_data();
        repeat(10) @(posedge clk);

        // ========== Test Case 5: 背压测试 ==========
        test_case = 5;
        $display("\n[Test Case %0d] Backpressure Test", test_case);
        config_truncation(0, 0);
        
        // 启动背压接收
        receive_data(1, 30);
        
        // 持续发送数据
        send_data(16'h0011, 0);
        send_data(16'h0022, 0);
        send_data(16'h0033, 0);
        send_data(-16'd50, 0);
        send_data(16'h0044, 0);
        
        final_out_ready = 1;  // 恢复就绪
        wait_all_data();
        repeat(30) @(posedge clk);
        final_out_ready = 0;

        // ========== Test Case 6: 边界条件测试 ==========
        test_case = 6;
        $display("\n[Test Case %0d] Boundary Test", test_case);
        config_truncation(0, 1);
        final_out_ready = 1;
        
        send_data(16'h7FFF, 0);  // 最大正数
        send_data(16'h8000, 0);  // 最小负数 -> ReLU输出0
        send_data(16'h0000, 0);  // 零
        send_data(16'hFFFF, 0);  // -1 -> ReLU输出0
        
        wait_all_data();
        repeat(10) @(posedge clk);

        // ========== Test Case 7: 随机发送测试 ==========
        test_case = 7;
        $display("\n[Test Case %0d] Random Send Test", test_case);
        config_truncation(2, 1);
        final_out_ready = 1;
        
        send_data(16'h0155, 1);  // 随机间隔发送
        send_data(-16'd200, 1);
        send_data(16'h0FFF, 1);
        send_data(16'h0033, 1);
        
        wait_all_data();
        repeat(15) @(posedge clk);

        // ========== Test Case 8: RELU关闭发送测试 ==========
        test_case = 8;
        relu_en = 0;
        cfg_en = 1;
        #10 cfg_en = 0;
        config_truncation(2, 1);
        final_out_ready = 1;
        
        send_data(16'h0155, 1);  // 随机间隔发送
        send_data(-16'd200, 1);
        send_data(16'h0FFF, 1);
        send_data(16'h0033, 1);
        
        wait_all_data();
        repeat(15) @(posedge clk);

        // ========== 测试结束 ==========
        $display("\n========================================");
        $display("  Test Summary:");
        $display("  Data Sent:     %0d", data_sent);
        $display("  Data Received: %0d", data_received);
        $display("  Passed:        %0d", passed);
        $display("  Errors:        %0d", errors);
        if (errors == 0) begin
            $display("  Status:        ✓ ALL TESTS PASSED!");
        end else begin
            $display("  Status:        ✗ SOME TESTS FAILED!");
        end
        $display("========================================");
        
        repeat(10) @(posedge clk);
        $finish;
    end

    // ========== 超时保护 ==========
    initial begin
        #50000;
        $display("\n[%0t] ERROR: Simulation Timeout!", $time);
        $finish;
    end

    // ========== 波形记录 ==========
    initial begin
        $dumpfile("tb_trunc_relu.vcd");
        $dumpvars(0, tb_trunc_relu);
    end

endmodule