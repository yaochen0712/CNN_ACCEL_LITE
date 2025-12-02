`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: tb_accumulator_unit
// Description: Testbench for Accumulator_unit
//              - 测试基本累加功能
//              - 测试溢出检测（上溢出和下溢出）
//              - 测试clear和sum_out控制
//              - 测试正负数混合累加
//              - 自动结果检查
//////////////////////////////////////////////////////////////////////////////////

module tb_accumulator_unit();

    // ========== 参数定义 ==========
    parameter DIN_WIDTH = 16;
    parameter DOUT_WIDTH = 24;
    parameter CLK_PERIOD = 10;

    // ========== 时钟 ==========
    reg clk;

    // ========== 控制信号 ==========
    reg clear;
    reg sum_out;
    reg en;
    // ========== 输入数据 ==========
    reg signed [DIN_WIDTH-1:0] data_in;
    reg data_in_valid;

    // ========== 输出数据 ==========
    wire signed [DOUT_WIDTH-1:0] data_out;
    wire [1:0] overflow;

    // ========== 测试控制 ==========
    integer test_case;
    integer i;
    integer errors;
    integer passed;
    reg signed [DOUT_WIDTH-1:0] expected_sum;

    // ========== DUT实例化 ==========
    Accumulator_unit #(
        .DIN_WIDTH(DIN_WIDTH),
        .DOUT_WIDTH(DOUT_WIDTH)
    ) u_accumulator (
        .clk(clk),
        .clear(clear),
        .i_data_in(data_in),
        .i_data_in_valid(data_in_valid),
        .i_sum_out(sum_out),
        .o_data_out(data_out),
        .o_accumulator_overflow(overflow)
    );

    // ========== 时钟生成 ==========
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ========== 监控输出 ==========
    always @(posedge clk) begin
        if (data_in_valid) begin
            $display("[%0t] Input: data_in=%0d (0x%h)", $time, $signed(data_in), data_in);
        end
        if (sum_out) begin
            $display("[%0t] Output: data_out=%0d (0x%h), overflow=%b", 
                     $time, $signed(data_out), data_out, overflow);
        end
    end

    // ========== Task: 初始化 ==========
    task init_signals;
        begin
            $display("\n[%0t] ========== Initialize Signals ==========", $time);
            clear = 0;
            sum_out = 0;
            data_in = 0;
            data_in_valid = 0;
            errors = 0;
            passed = 0;
            expected_sum = 0;
            en = 1;
            // 使用clear信号清零
            @(posedge clk);
            clear = 1;
            @(posedge clk);
            clear = 0;
            repeat(2) @(posedge clk);
            $display("[%0t] ========== Initialization Done ==========", $time);
        end
    endtask

    // ========== Task: 发送数据 ==========
    task send_data;
        input signed [DIN_WIDTH-1:0] value;
        begin
            @(posedge clk);
            data_in = value;
            data_in_valid = 1;
            expected_sum = expected_sum + value;
            @(posedge clk);
            data_in_valid = 0;
        end
    endtask

    // ========== Task: 读取累加结果 ==========
    task read_sum;
        input signed [DOUT_WIDTH-1:0] expected;
        input [1:0] expected_overflow;
        begin
            @(posedge clk);
            sum_out = 1;
            @(posedge clk);
            sum_out = 0;
            @(posedge clk);
            
            // 检查结果
            if (data_out === expected && overflow === expected_overflow) begin
                $display("[%0t]    PASS: Sum=%0d, Overflow=%b", $time, $signed(data_out), overflow);
                passed = passed + 1;
            end else begin
                $display("[%0t]    FAIL: Sum=%0d (expected %0d), Overflow=%b (expected %b)", 
                         $time, $signed(data_out), $signed(expected), overflow, expected_overflow);
                errors = errors + 1;
            end
            
            // 清零预期值
            expected_sum = 0;
        end
    endtask

    // ========== Task: 测试清零 ==========
    task test_clear;
        begin
            @(posedge clk);
            clear = 1;
            @(posedge clk);
            clear = 0;
            @(posedge clk);
            expected_sum = 0;
            $display("[%0t] Clear signal asserted", $time);
        end
    endtask

    // ========== 主测试流程 ==========
    initial begin
        $display("========================================");
        $display("  Accumulator Unit Testbench Start");
        $display("========================================");
        
        // ========== Test Case 0: 初始化测试 ==========
        test_case = 0;
        $display("\n[Test Case %0d] Initialization Test", test_case);
        init_signals();

        // ========== Test Case 1: 基本累加测试（正数） ==========
        test_case = 1;
        $display("\n[Test Case %0d] Basic Accumulation (Positive Numbers)", test_case);
        
        send_data(16'd100);   // 累加100
        send_data(16'd200);   // 累加200
        send_data(16'd300);   // 累加300
        // 预期和 = 600
        repeat(2) @(posedge clk);
        read_sum(32'd600, 2'b00);

        // ========== Test Case 2: 负数累加测试 ==========
        test_case = 2;
        $display("\n[Test Case %0d] Negative Number Accumulation", test_case);
        
        send_data(-16'd50);   // 累加-50
        send_data(-16'd100);  // 累加-100
        send_data(-16'd150);  // 累加-150
        // 预期和 = -300
        repeat(2) @(posedge clk);
        read_sum(-32'd300, 2'b00);

        // ========== Test Case 3: 正负混合累加 ==========
        test_case = 3;
        $display("\n[Test Case %0d] Mixed Positive and Negative", test_case);
        
        send_data(16'd1000);   // +1000
        send_data(-16'd300);   // -300
        send_data(16'd500);    // +500
        send_data(-16'd200);   // -200
        // 预期和 = 1000
        repeat(2) @(posedge clk);
        read_sum(32'd1000, 2'b00);

        // ========== Test Case 4: Clear信号测试 ==========
        test_case = 4;
        $display("\n[Test Case %0d] Clear Signal Test", test_case);
        
        send_data(16'd1234);
        send_data(16'd5678);
        repeat(2) @(posedge clk);
        
        // 使用clear清零
        test_clear();
        repeat(2) @(posedge clk);
        
        // 读取应该为0
        read_sum(32'd0, 2'b00);

        // ========== Test Case 5: 连续累加和读取 ==========
        test_case = 5;
        $display("\n[Test Case %0d] Continuous Accumulation and Read", test_case);
        
        // 第一组
        send_data(16'd10);
        send_data(16'd20);
        send_data(16'd30);
        read_sum(32'd60, 2'b00);
        
        // 第二组（累加器已清零）
        send_data(16'd100);
        send_data(16'd200);
        read_sum(32'd300, 2'b00);

        // ========== Test Case 6: 边界值测试 ==========
        test_case = 6;
        $display("\n[Test Case %0d] Boundary Value Test", test_case);
        
        // 最大正数
        send_data(16'h7FFF);  // 32767
        send_data(16'd1);
        read_sum(32'd32768, 2'b00);
        
        // 最小负数
        send_data(-16'h8000); // -32768
        send_data(-16'd1);
        read_sum(-32'd32769, 2'b00);

        // ========== Test Case 7: 上溢出测试 ==========
        test_case = 7;
        $display("\n[Test Case %0d] Positive Overflow Test", test_case);
        
        // 使用较小的位宽演示溢出
        // 累加接近32位最大值
        send_data(16'h7FFF);  // 32767
        repeat(258) begin
            send_data(16'h7FFF);
        end
        repeat(2) @(posedge clk);
        
        // 检查溢出标志
        @(posedge clk);
        sum_out = 1;
        @(posedge clk);
        sum_out = 0;
        @(posedge clk);
        
        if (overflow[0] == 1'b1) begin
            $display("[%0t]    PASS: Positive overflow detected, overflow=%b", $time, overflow);
            passed = passed + 1;
        end else begin
            $display("[%0t]    FAIL: Positive overflow not detected, overflow=%b", $time, overflow);
            errors = errors + 1;
        end
        expected_sum = 0;

        // ========== Test Case 8: 下溢出测试 ==========
        test_case = 8;
        $display("\n[Test Case %0d] Negative Overflow Test", test_case);
        
        // 累加接近32位最小值
        send_data(-16'h8000);  // -32768
        repeat(258) begin
            send_data(-16'h8000);
        end
        repeat(2) @(posedge clk);
        
        // 检查溢出标志
        @(posedge clk);
        sum_out = 1;
        @(posedge clk);
        sum_out = 0;
        @(posedge clk);
        
        if (overflow[1] == 1'b1) begin
            $display("[%0t]    PASS: Negative overflow detected, overflow=%b", $time, overflow);
            passed = passed + 1;
        end else begin
            $display("[%0t]    FAIL: Negative overflow not detected, overflow=%b", $time, overflow);
            errors = errors + 1;
        end
        expected_sum = 0;

        // ========== Test Case 9: 零值累加 ==========
        test_case = 9;
        $display("\n[Test Case %0d] Zero Accumulation Test", test_case);
        
        send_data(16'd0);
        send_data(16'd0);
        send_data(16'd0);
        read_sum(32'd0, 2'b00);

         // ========== Test Case 10: Valid信号间歇性测试 ==========
        test_case = 10;
        $display("\n[Test Case %0d] Intermittent Valid Signal Test", test_case);
        
        send_data(16'd50);
        repeat(3) @(posedge clk);  // 等待几个周期
        send_data(16'd100);
        repeat(2) @(posedge clk);
        send_data(16'd150);
        read_sum(32'd300, 2'b00);

        // ========== Test Case 11: 数据握手后立即sum_out ==========
        test_case = 11;
        $display("\n[Test Case %0d] Immediate sum_out After Last Data Handshake", test_case);
        
        expected_sum = 0;
        
        // 发送第一个数据
        @(posedge clk);
        data_in = 16'd10;
        data_in_valid = 1;
        expected_sum = expected_sum + 16'd10;
        @(posedge clk);
        data_in_valid = 0;
        
        // 发送第二个数据
        @(posedge clk);
        data_in = 16'd20;
        data_in_valid = 1;
        expected_sum = expected_sum + 16'd20;
        @(posedge clk);
        data_in_valid = 0;
        
        // 发送第三个数据，并在握手后立即拉高sum_out
        @(posedge clk);
        data_in = 16'd30;
        data_in_valid = 1;
        expected_sum = expected_sum + 16'd30;  // 总和应该是60
        
        @(posedge clk);  // 数据握手发生
        data_in_valid = 0;
        sum_out = 1;     // 立即拉高sum_out（与数据握手同一周期的下降沿）
        
        @(posedge clk);  // sum_out生效
        sum_out = 0;
        
        @(posedge clk);  // 检查输出
        
        // 检查结果
        if (data_out === 32'd60 && overflow === 2'b00) begin
            $display("[%0t]   PASS: Immediate sum_out works, Sum=%0d, Overflow=%b", 
                     $time, $signed(data_out), overflow);
            passed = passed + 1;
        end else begin
            $display("[%0t]   FAIL: Sum=%0d (expected 60), Overflow=%b (expected 00)", 
                     $time, $signed(data_out), overflow);
            errors = errors + 1;
        end
        
        expected_sum = 0;

        // ========== Test Case 12: 流水线式连续累加和输出 ==========
        test_case = 12;
        $display("\n[Test Case %0d] Pipelined Continuous Accumulation", test_case);
        
        expected_sum = 0;
        
        // 第一组：累加3个数
        $display("  --- Group 1 ---");
        @(posedge clk);
        data_in = 16'd5;
        data_in_valid = 1;
        expected_sum = 16'd5;
        
        @(posedge clk);
        data_in = 16'd10;
        data_in_valid = 1;
        expected_sum = expected_sum + 16'd10;
        
        @(posedge clk);
        data_in = 16'd15;
        data_in_valid = 1;
        expected_sum = expected_sum + 16'd15;  // 总和30
        
        @(posedge clk);
        data_in_valid = 0;
        sum_out = 1;  // 立即输出
        
        @(posedge clk);
        sum_out = 0;
        
        @(posedge clk);
        if (data_out === 32'd30 && overflow === 2'b00) begin
            $display("[%0t]   PASS: Group 1, Sum=%0d", $time, $signed(data_out));
            passed = passed + 1;
        end else begin
            $display("[%0t]   FAIL: Group 1, Sum=%0d (expected 30)", $time, $signed(data_out));
            errors = errors + 1;
        end
        
        // 第二组：累加2个数（立即开始，无等待）
        $display("  --- Group 2 ---");
        expected_sum = 0;
        
        @(posedge clk);
        data_in = 16'd100;
        data_in_valid = 1;
        expected_sum = 16'd100;
        
        @(posedge clk);
        data_in = 16'd200;
        data_in_valid = 1;
        expected_sum = expected_sum + 16'd200;  // 总和300
        
        @(posedge clk);
        data_in_valid = 0;
        sum_out = 1;  // 立即输出
        
        @(posedge clk);
        sum_out = 0;
        
        @(posedge clk);
        if (data_out === 32'd300 && overflow === 2'b00) begin
            $display("[%0t]   PASS: Group 2, Sum=%0d", $time, $signed(data_out));
            passed = passed + 1;
        end else begin
            $display("[%0t]   FAIL: Group 2, Sum=%0d (expected 300)", $time, $signed(data_out));
            errors = errors + 1;
        end
        
        expected_sum = 0;

        // ========== Test Case 13: 单个数据后立即输出 ==========
        test_case = 13;
        $display("\n[Test Case %0d] Single Data with Immediate sum_out", test_case);
        
        @(posedge clk);
        data_in = 16'd999;
        data_in_valid = 1;
        
        @(posedge clk);
        data_in_valid = 0;
        sum_out = 1;  // 单个数据后立即输出
        
        @(posedge clk);
        sum_out = 0;
        
        @(posedge clk);
        if (data_out === 32'd999 && overflow === 2'b00) begin
            $display("[%0t]   PASS: Single data, Sum=%0d", $time, $signed(data_out));
            passed = passed + 1;
        end else begin
            $display("[%0t]   FAIL: Single data, Sum=%0d (expected 999)", $time, $signed(data_out));
            errors = errors + 1;
        end

        // ========== Test Case 14: 流水线高强度数据测试 ==========
        test_case = 14;
        $display("\n[Test Case %0d] High Intensity Pipeline Data Stream Test", test_case);
        
        expected_sum = 0;
        
        // 子测试 14.1: 连续正数流水线
        $display("  --- Subtest 14.1: Continuous Positive Data Stream ---");
        @(posedge clk);
        data_in_valid = 1;  // 拉高valid信号，保持到子测试结束
        
        // 连续发送20个递增的正数
        for (i = 1; i <= 20; i = i + 1) begin
            @(posedge clk);
            data_in = i * 10;  // 10, 20, 30, ..., 200
            expected_sum = expected_sum + (i * 10);
            $display("[%0t]   Sending data: %0d, Running expected sum: %0d", 
                     $time, i * 10, expected_sum);
        end
        
        @(posedge clk);
        data_in_valid = 0;  // 停止发送数据
        
        repeat(2) @(posedge clk);  // 等待数据稳定
        
        // 读取累加结果 (1+2+...+20)*10 = 210*10 = 2100
        @(posedge clk);
        sum_out = 1;
        @(posedge clk);
        sum_out = 0;
        @(posedge clk);
        
        if (data_out === 32'd2100 && overflow === 2'b00) begin
            $display("[%0t]   PASS: Continuous positive stream, Sum=%0d", $time, $signed(data_out));
            passed = passed + 1;
        end else begin
            $display("[%0t]   FAIL: Sum=%0d (expected 2100), Overflow=%b", 
                     $time, $signed(data_out), overflow);
            errors = errors + 1;
        end
        
        // 子测试 14.2: 连续负数流水线
        $display("  --- Subtest 14.2: Continuous Negative Data Stream ---");
        expected_sum = 0;
        
        @(posedge clk);
        data_in_valid = 1;  // 重新拉高valid信号
        
        // 连续发送15个递减的负数
        for (i = 1; i <= 15; i = i + 1) begin
            @(posedge clk);
            data_in = -(i * 20);  // -20, -40, -60, ..., -300
            expected_sum = expected_sum - (i * 20);
            if (i <= 5) begin  // 只显示前5个，避免输出过多
                $display("[%0t]   Sending data: %0d, Running expected sum: %0d", 
                         $time, -(i * 20), expected_sum);
            end
        end
        
        @(posedge clk);
        data_in_valid = 0;
        
        repeat(2) @(posedge clk);
        
        // 读取累加结果 -(1+2+...+15)*20 = -120*20 = -2400
        @(posedge clk);
        sum_out = 1;
        @(posedge clk);
        sum_out = 0;
        @(posedge clk);
        
        if (data_out === -32'd2400 && overflow === 2'b00) begin
            $display("[%0t]   PASS: Continuous negative stream, Sum=%0d", $time, $signed(data_out));
            passed = passed + 1;
        end else begin
            $display("[%0t]   FAIL: Sum=%0d (expected -2400), Overflow=%b", 
                     $time, $signed(data_out), overflow);
            errors = errors + 1;
        end
        
        // 子测试 14.3: 正负交替高频流水线
        $display("  --- Subtest 14.3: Alternating Positive/Negative High Frequency Stream ---");
        expected_sum = 0;
        
        @(posedge clk);
        data_in_valid = 1;
        
        // 发送25个正负交替的数据
        for (i = 0; i < 25; i = i + 1) begin
            @(posedge clk);
            if (i % 2 == 0) begin
                data_in = 16'd50;   // 偶数索引发送+50
                expected_sum = expected_sum + 50;
            end else begin
                data_in = -16'd30;  // 奇数索引发送-30
                expected_sum = expected_sum - 30;
            end
            
            if (i < 6) begin  // 只显示前6个
                $display("[%0t]   Sending data[%0d]: %0d, Expected sum: %0d", 
                         $time, i, $signed(data_in), expected_sum);
            end
        end
        
        @(posedge clk);
        data_in_valid = 0;
        
        repeat(2) @(posedge clk);
        
        // 计算预期结果：13个+50和12个-30 = 13*50 - 12*30 = 650 - 360 = 290
        @(posedge clk);
        sum_out = 1;
        @(posedge clk);
        sum_out = 0;
        @(posedge clk);
        
        if (data_out === 32'd290 && overflow === 2'b00) begin
            $display("[%0t]   PASS: Alternating stream, Sum=%0d", $time, $signed(data_out));
            passed = passed + 1;
        end else begin
            $display("[%0t]   FAIL: Sum=%0d (expected 290), Overflow=%b", 
                     $time, $signed(data_out), overflow);
            errors = errors + 1;
        end
        
        // 子测试 14.4: 高频流水线中途sum_out测试
        $display("  --- Subtest 14.4: Mid-stream sum_out During High Frequency Data ---");
        expected_sum = 0;
        
        @(posedge clk);
        data_in_valid = 1;
        
        // 发送前10个数据
        for (i = 1; i <= 10; i = i + 1) begin
            @(posedge clk);
            data_in = i * 5;  // 5, 10, 15, ..., 50
            expected_sum = expected_sum + (i * 5);
        end
        
        // 在数据流中途进行sum_out（不停止数据流）
        @(posedge clk);
        data_in = 16'd100;  // 继续发送数据
        expected_sum = expected_sum + 100;  // 但这个不应该被当前sum_out读取
        sum_out = 1;  // 同时拉高sum_out
        
        // sum_out应该读取前10个数据的和：(1+2+...+10)*5 = 55*5 = 275
        @(posedge clk);
        data_in = 16'd200;  // 继续发送
        sum_out = 0;  // 结束sum_out
        
        @(posedge clk);
        data_in_valid = 0;  // 停止数据流
        
        @(posedge clk);
        
        if (data_out === 32'd275 && overflow === 2'b00) begin
            $display("[%0t]   PASS: Mid-stream sum_out, Sum=%0d", $time, $signed(data_out));
            passed = passed + 1;
        end else begin
            $display("[%0t]   FAIL: Sum=%0d (expected 275), Overflow=%b", 
                     $time, $signed(data_out), overflow);
            errors = errors + 1;
        end
        
        // 子测试 14.5: 背靠背（Back-to-back）累加组测试
        $display("  --- Subtest 14.5: Back-to-back Accumulation Groups ---");
        
        // 第一组：快速累加5个数并立即输出
        expected_sum = 0;
        @(posedge clk);
        data_in_valid = 1;
        
        for (i = 1; i <= 5; i = i + 1) begin
            @(posedge clk);
            data_in = i * 100;  // 100, 200, 300, 400, 500
            expected_sum = expected_sum + (i * 100);
        end
        
        @(posedge clk);
        data_in_valid = 0;
        sum_out = 1;  // 立即输出
        
        @(posedge clk);
        sum_out = 0;
        
        @(posedge clk);
        if (data_out === 32'd1500 && overflow === 2'b00) begin  // (1+2+3+4+5)*100 = 1500
            $display("[%0t]   PASS: Back-to-back Group 1, Sum=%0d", $time, $signed(data_out));
            passed = passed + 1;
        end else begin
            $display("[%0t]   FAIL: Group 1, Sum=%0d (expected 1500)", $time, $signed(data_out));
            errors = errors + 1;
        end
        
        // 第二组：无延迟立即开始下一组
        expected_sum = 0;
        @(posedge clk);
        data_in_valid = 1;
        
        for (i = 1; i <= 3; i = i + 1) begin
            @(posedge clk);
            data_in = -(i * 150);  // -150, -300, -450
            expected_sum = expected_sum - (i * 150);
        end
        
        @(posedge clk);
        data_in_valid = 0;
        sum_out = 1;
        
        @(posedge clk);
        sum_out = 0;
        
        @(posedge clk);
        if (data_out === -32'd900 && overflow === 2'b00) begin  // -(1+2+3)*150 = -900
            $display("[%0t]   PASS: Back-to-back Group 2, Sum=%0d", $time, $signed(data_out));
            passed = passed + 1;
        end else begin
            $display("[%0t]   FAIL: Group 2, Sum=%0d (expected -900)", $time, $signed(data_out));
            errors = errors + 1;
        end
        
        $display("  --- Test Case 14 Complete: High Intensity Pipeline Test ---");

        // ========== 测试结束 ==========

        // ========== 测试结束 ==========
        repeat(10) @(posedge clk);
        $display("\n========================================");
        $display("  Test Summary:");
        $display("  Passed: %0d", passed);
        $display("  Errors: %0d", errors);
        if (errors == 0) begin
            $display("  Status:    ALL TESTS PASSED!");
        end else begin
            $display("  Status:    SOME TESTS FAILED!");
        end
        $display("========================================");
        
        $finish;
    end

    // ========== 超时保护 ==========
    initial begin
        #400000;
        $display("\n[%0t] ERROR: Simulation Timeout!", $time);
        $finish;
    end

    // ========== 波形记录 ==========
    initial begin
        $dumpfile("tb_accumulator_unit.vcd");
        $dumpvars(0, tb_accumulator_unit);
    end

endmodule