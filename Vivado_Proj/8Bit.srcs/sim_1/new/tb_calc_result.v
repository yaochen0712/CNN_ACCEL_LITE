`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: tb_calc_result
// Description: caluc_result模块的testbench
//              - 测试串行接收A和B数据
//              - 测试有符号数比较（正数、负数、相等）
//              - 测试输出格式化（32bit = {16{result}, A, B}）
//              - 测试连续多组数据处理
//////////////////////////////////////////////////////////////////////////////////

module tb_calc_result();

    // 参数定义
    localparam CLK_PERIOD = 10;
    
    // 时钟和复位
    reg clk;
    reg rst_n;
    
    // 输入信号
    reg [7:0] result_data_in;
    reg result_data_valid;
    wire result_data_ready;
    
    // 输出信号
    wire [31:0] trans_data;
    wire trans_valid;
    reg trans_ready;
    
    // 测试变量
    integer test_count;
    integer pass_count;
    integer fail_count;
    
    // 时钟生成
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // DUT实例化
    caluc_result u_caluc_result(
        .clk(clk),
        .rst_n(rst_n),
        .i_result_data_in(result_data_in),
        .i_result_data_valid(result_data_valid),
        .o_result_data_ready(result_data_ready),
        .o_trans_data(trans_data),
        .o_trans_valid(trans_valid),
        .i_trans_ready(trans_ready)
    );
    
    // 握手信号
    wire input_handshake = result_data_valid && result_data_ready;
    wire output_handshake = trans_valid && trans_ready;
    
    // 主测试流程
    initial begin
        $display("\n========== caluc_result Testbench Start ==========\n");
        
        // 初始化
        initialize();
        
        // 测试1: A > B (正数)
        $display("\n[Test 1] A > B (Positive Numbers)");
        test_comparison(8'sd50, 8'sd30, 1'b1);
        
        // 测试2: A < B (正数)
        $display("\n[Test 2] A < B (Positive Numbers)");
        test_comparison(8'sd20, 8'sd40, 1'b0);
        
        // 测试3: A == B (相等)
        $display("\n[Test 3] A == B (Equal)");
        test_comparison(8'sd35, 8'sd35, 1'b0);
        
        // 测试4: A > B (负数)
        $display("\n[Test 4] A > B (Negative Numbers)");
        test_comparison(-8'sd10, -8'sd20, 1'b1);
        
        // 测试5: A < B (负数)
        $display("\n[Test 5] A < B (Negative Numbers)");
        test_comparison(-8'sd30, -8'sd15, 1'b0);
        
        // 测试6: A(正) > B(负)
        $display("\n[Test 6] A(Positive) > B(Negative)");
        test_comparison(8'sd25, -8'sd10, 1'b1);
        
        // 测试7: A(负) < B(正)
        $display("\n[Test 7] A(Negative) < B(Positive)");
        test_comparison(-8'sd5, 8'sd15, 1'b0);
        
        // 测试8: 连续多组数据
        $display("\n[Test 8] Multiple Continuous Comparisons");
        test_continuous();
        
        // 测试9: 下游反压测试
        $display("\n[Test 9] Downstream Backpressure Test");
        test_backpressure();
        
        // 测试完成
        repeat(20) @(posedge clk);
        
        $display("\n========== Test Summary ==========");
        $display("Total Tests: %0d", test_count);
        $display("Passed:      %0d", pass_count);
        $display("Failed:      %0d", fail_count);
        if (fail_count == 0) begin
            $display("Status:      ALL TESTS PASSED!");
        end else begin
            $display("Status:      SOME TESTS FAILED!");
        end
        $display("==================================\n");
        
        $finish;
    end
    
    // 初始化任务
    task initialize();
        begin
            rst_n = 0;
            result_data_in = 8'd0;
            result_data_valid = 0;
            trans_ready = 0;
            test_count = 0;
            pass_count = 0;
            fail_count = 0;
            
            repeat(10) @(posedge clk);
            rst_n = 1;
            repeat(5) @(posedge clk);
        end
    endtask
    
    // 单次比较测试任务
    task test_comparison(
        input signed [7:0] data_a,
        input signed [7:0] data_b,
        input expected_result
    );
        reg [31:0] expected_output;
        reg [31:0] actual_output;
        begin
            test_count = test_count + 1;
            expected_output = {{16{expected_result}}, data_a, data_b};
            
            $display("  Input: A=%0d, B=%0d, Expected: %s", 
                     $signed(data_a), $signed(data_b), 
                     expected_result ? "A>B" : "A<=B");
            
            // 连续发送A和B，valid保持拉高
            @(posedge clk);
            result_data_in = data_a;
            result_data_valid = 1;
            wait(input_handshake);
            
            // A握手完成后立即发送B
            @(posedge clk);
            result_data_in = data_b;
            // valid保持拉高
            wait(input_handshake);
            
            // B握手完成后才拉低valid
            @(posedge clk);
            result_data_valid = 0;
            
            // 等待输出
            trans_ready = 1;
            wait(trans_valid);
            @(posedge clk);
            actual_output = trans_data;
            
            // 验证结果
            if (actual_output == expected_output) begin
                $display("  Output: 0x%08h [PASS]", actual_output);
                pass_count = pass_count + 1;
            end else begin
                $display("  Output: 0x%08h [FAIL] Expected: 0x%08h", 
                         actual_output, expected_output);
                fail_count = fail_count + 1;
            end
            
            wait(output_handshake);
            @(posedge clk);
            trans_ready = 0;
            
            repeat(3) @(posedge clk);
        end
    endtask
    
    // 连续多组数据测试
    task test_continuous();
        integer i;
        reg signed [7:0] test_a[0:4];
        reg signed [7:0] test_b[0:4];
        reg test_result[0:4];
        begin
            // 准备测试数据
            test_a[0] = 8'sd10;  test_b[0] = 8'sd5;   test_result[0] = 1;  // 10 > 5
            test_a[1] = -8'sd3;  test_b[1] = 8'sd7;   test_result[1] = 0;  // -3 < 7
            test_a[2] = 8'sd50;  test_b[2] = 8'sd50;  test_result[2] = 0;  // 50 == 50
            test_a[3] = -8'sd20; test_b[3] = -8'sd25; test_result[3] = 1;  // -20 > -25
            test_a[4] = 8'sd127; test_b[4] = -8'sd128; test_result[4] = 1; // max > min
            
            trans_ready = 1;  // 下游一直准备好
            
            for (i = 0; i < 5; i = i + 1) begin
                test_count = test_count + 1;
                $display("  Group %0d: A=%0d, B=%0d", i+1, $signed(test_a[i]), $signed(test_b[i]));
                
                // 连续发送A和B
                @(posedge clk);
                result_data_in = test_a[i];
                result_data_valid = 1;
                wait(input_handshake);
                
                // A握手后立即发送B
                @(posedge clk);
                result_data_in = test_b[i];
                // valid保持拉高
                wait(input_handshake);
                
                // B握手后如果不是最后一组，继续保持valid拉高
                // 如果是最后一组，拉低valid
                if (i == 4) begin
                    @(posedge clk);
                    result_data_valid = 0;
                end
                
                // 等待并验证输出
                wait(output_handshake);
                
                if (trans_data[31:16] == {16{test_result[i]}} &&
                    trans_data[15:8] == test_a[i] &&
                    trans_data[7:0] == test_b[i]) begin
                    $display("    Result: 0x%08h [PASS]", trans_data);
                    pass_count = pass_count + 1;
                end else begin
                    $display("    Result: 0x%08h [FAIL]", trans_data);
                    fail_count = fail_count + 1;
                end
                
                @(posedge clk);
            end
            
            trans_ready = 0;
            repeat(5) @(posedge clk);
        end
    endtask
    
    // 反压测试
    task test_backpressure();
        reg signed [7:0] test_a;
        reg signed [7:0] test_b;
        integer wait_cycles;
        begin
            test_count = test_count + 1;
            test_a = 8'sd60;
            test_b = 8'sd45;
            
            $display("  Testing backpressure with A=%0d, B=%0d", $signed(test_a), $signed(test_b));
            
            // 连续发送A和B
            @(posedge clk);
            result_data_in = test_a;
            result_data_valid = 1;
            wait(input_handshake);
            
            // A握手后立即发送B
            @(posedge clk);
            result_data_in = test_b;
            // valid保持拉高
            wait(input_handshake);
            
            // B握手后拉低valid
            @(posedge clk);
            result_data_valid = 0;
            
            // 等待输出valid
            wait(trans_valid);
            $display("  Output valid asserted");
            
            // 延迟ready响应（模拟反压）
            trans_ready = 0;
            wait_cycles = 10;
            repeat(wait_cycles) @(posedge clk);
            $display("  Backpressure released after %0d cycles", wait_cycles);
            
            // 拉高ready并接收
            trans_ready = 1;
            wait(output_handshake);
            
            if (trans_data[31:16] == 16'hFFFF &&
                trans_data[15:8] == test_a &&
                trans_data[7:0] == test_b) begin
                $display("  Result: 0x%08h [PASS]", trans_data);
                pass_count = pass_count + 1;
            end else begin
                $display("  Result: 0x%08h [FAIL]", trans_data);
                fail_count = fail_count + 1;
            end
            
            @(posedge clk);
            trans_ready = 0;
            repeat(3) @(posedge clk);
        end
    endtask
    
    // 超时保护
    initial begin
        #(CLK_PERIOD * 10000);
        $display("ERROR: Simulation timeout!");
        $finish;
    end
    
    // 波形文件
    initial begin
        $dumpfile("tb_calc_result.vcd");
        $dumpvars(0, tb_calc_result);
    end

endmodule
