`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: tb_Cache
// Description: Testbench for Cache module (Parallel to Serial with Gating)
//              - 简化版本：8通道，方便调试和波形观察
//              - 测试并行到串行转换
//              - 测试门控功能（不同的有效通道数）
//              - 测试握手协议
//              - 自动结果检查
//////////////////////////////////////////////////////////////////////////////////

module tb_Cache();

    // ========== 参数定义 ==========
    parameter D_WIDTH = 8;
    parameter CHANNEL = 8;       // 简化为8通道
    parameter GATE_PARA = 2;     // 2位门控 (2^2 = 4组)
    parameter CLK_PERIOD = 10;

    // ========== 时钟和复位 ==========
    reg clk;
    reg rst_n;

    // ========== 配置接口 ==========
    reg [$clog2(GATE_PARA):0] cfg_gate_en;
    reg cfg_valid;

    // ========== 上游并行数据接口 ==========
    reg [D_WIDTH*CHANNEL-1:0] data_parallel;
    reg data_parallel_valid;
    wire data_parallel_ready;

    // ========== 下游串行数据接口 ==========
    wire [D_WIDTH-1:0] data_serial;
    wire data_serial_valid;
    reg data_serial_ready;

    // ========== 状态输出 ==========
    wire mem_full;
    wire mem_empty;

    // ========== 测试控制 ==========
    integer test_case;
    integer data_sent;
    integer data_received;
    integer errors;
    integer passed;
    integer expected_count;
    
    // ========== 预期值队列 ==========
    reg [D_WIDTH-1:0] expected_queue [0:CHANNEL-1];
    integer queue_size;
    integer queue_rd_ptr;

    // ========== DUT实例化 ==========
    Cache #(
        .D_WIDTH(D_WIDTH),
        .CHANNEL(CHANNEL),
        .GATE_PARA(GATE_PARA)
    ) u_cache (
        .clk(clk),
        .rst_n(rst_n),
        .i_cfg_gate_en(cfg_gate_en),
        .i_cfg_valid(cfg_valid),
        .i_data_parallel(data_parallel),
        .i_data_parallel_valid(data_parallel_valid),
        .o_data_parallel_ready(data_parallel_ready),
        .o_data_serial(data_serial),
        .o_data_serial_valid(data_serial_valid),
        .i_data_serial_ready(data_serial_ready),
        .o_mem_full(mem_full),
        .o_mem_empty(mem_empty)
    );

    // ========== 时钟生成 ==========
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ========== 握手检测 ==========
    wire input_handshake = data_parallel_valid && data_parallel_ready;
    wire output_handshake = data_serial_valid && data_serial_ready;

    // ========== 监控输出 ==========
    always @(posedge clk) begin
        if (input_handshake) begin
            $display("[%0t] Input Handshake: Parallel data loaded = %h", $time, data_parallel);
        end
        if (output_handshake) begin
            $display("[%0t] Output Handshake: Channel[%0d] = 0x%h (expected = 0x%h)", 
                     $time, queue_rd_ptr, data_serial, expected_queue[queue_rd_ptr]);
        end
    end

    // ========== 计算有效通道数 ==========
    function integer calc_valid_channels;
        input [$clog2(GATE_PARA):0] gate_en;
        begin
            // 有效通道数 = (CHANNEL / 2^GATE_PARA) * (2^gate_en)
            // CHANNEL=8, GATE_PARA=2: 每组2个通道
            // gate_en=0: 2通道, gate_en=1: 4通道, gate_en=2: 8通道
            calc_valid_channels = (CHANNEL >> GATE_PARA) << gate_en;
        end
    endfunction

    // ========== Task: 复位 ==========
    task reset_dut;
        begin
            $display("\n[%0t] ========== Reset Start ==========", $time);
            rst_n = 0;
            data_parallel = 0;
            data_parallel_valid = 0;
            data_serial_ready = 0;
            cfg_gate_en = 0;
            cfg_valid = 0;
            data_sent = 0;
            data_received = 0;
            errors = 0;
            passed = 0;
            queue_size = 0;
            queue_rd_ptr = 0;
            
            repeat(5) @(posedge clk);
            rst_n = 1;
            repeat(2) @(posedge clk);
            $display("[%0t] ========== Reset Done ==========", $time);
        end
    endtask

    // ========== Task: 配置门控 ==========
    task config_gating;
        input [GATE_PARA-1:0] gate_en;
        begin
            expected_count = calc_valid_channels(gate_en);
            $display("\n[%0t] Config Gating: gate_en=%0d, valid_channels=%0d/%0d", 
                     $time, gate_en, expected_count, CHANNEL);
            @(posedge clk);
            cfg_valid = 1;
            cfg_gate_en = gate_en;
            @(posedge clk);
            cfg_valid = 0;
            @(posedge clk);
        end
    endtask

    // ========== Task: 发送并行数据 ==========
    task send_parallel_data;
        input [D_WIDTH*CHANNEL-1:0] data;
        integer i;
        begin
            // 构建预期值队列（从低到高）
            queue_size = expected_count;
            $display("\n[%0t] Preparing to send parallel data:", $time);
            for (i = 0; i < expected_count; i = i + 1) begin
                expected_queue[i] = data[D_WIDTH*i +: D_WIDTH];
                $display("  Channel[%0d] = 0x%h", i, expected_queue[i]);
            end
            queue_rd_ptr = 0;
            
            // 发送数据
            @(posedge clk);
            data_parallel = data;
            data_parallel_valid = 1;
            
            // 等待握手
            @(posedge clk);
            while (!input_handshake) begin
                @(posedge clk);
            end
            
            $display("[%0t] Sent parallel data, expecting %0d serial outputs", 
                     $time, expected_count);
            data_sent = data_sent + 1;
            
            // 握手成功后拉低valid
            @(posedge clk);
            data_parallel_valid = 0;
        end
    endtask

    // ========== 结果检查 ==========
    always @(posedge clk) begin
        if (output_handshake) begin
            if (queue_rd_ptr < queue_size) begin
                if (data_serial === expected_queue[queue_rd_ptr]) begin
                    $display("[%0t] ✓ PASS: Channel[%0d] = 0x%h", 
                             $time, queue_rd_ptr, data_serial);
                    passed = passed + 1;
                end else begin
                    $display("[%0t] ✗ FAIL: Channel[%0d] = 0x%h, Expected = 0x%h", 
                             $time, queue_rd_ptr, data_serial, expected_queue[queue_rd_ptr]);
                    errors = errors + 1;
                end
                queue_rd_ptr = queue_rd_ptr + 1;
                data_received = data_received + 1;
            end else begin
                $display("[%0t] ✗ ERROR: Unexpected output! Already received all %0d expected data", 
                         $time, queue_size);
                errors = errors + 1;
            end
        end
    end

    // ========== Task: 等待所有串行数据输出 ==========
    task wait_serial_complete;
        integer timeout;
        begin
            timeout = 0;
            while (queue_rd_ptr < queue_size && timeout < 100) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (timeout >= 100) begin
                $display("[%0t] WARNING: Timeout waiting for serial output, received %0d/%0d", 
                         $time, queue_rd_ptr, queue_size);
            end else begin
                $display("[%0t] All %0d serial outputs received\n", $time, queue_size);
            end
        end
    endtask

    // ========== 主测试流程 ==========
    initial begin
        $display("========================================");
        $display("  Cache Module Testbench (8 Channels)");
        $display("========================================");
        
        // ========== Test Case 0: 复位测试 ==========
        test_case = 0;
        $display("\n[Test Case %0d] Reset Test", test_case);
        reset_dut();
        
        // 检查初始状态
        if (mem_empty && !mem_full && data_parallel_ready) begin
            $display("✓ Initial state correct: empty=1, full=0, ready=1");
        end else begin
            $display("✗ Initial state error!");
            errors = errors + 1;
        end

        // ========== Test Case 1: 全通道测试（8通道） ==========
        test_case = 1;
        $display("\n[Test Case %0d] All 8 Channels Enabled", test_case);
        config_gating(2);  // gate_en=2 -> 8通道
        data_serial_ready = 1;
        
        // 发送递增数据: CH0=0x11, CH1=0x22, ..., CH7=0x88
        send_parallel_data({8'h88, 8'h77, 8'h66, 8'h55, 8'h44, 8'h33, 8'h22, 8'h11});
        wait_serial_complete();
        repeat(5) @(posedge clk);

        // ========== Test Case 2: 4通道测试 ==========
        test_case = 2;
        $display("\n[Test Case %0d] 4 Channels Enabled", test_case);
        config_gating(1);  // gate_en=1 -> 4通道
        data_serial_ready = 1;
        
        // 发送数据，只有低4个通道有效
        send_parallel_data({8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hD4, 8'hC3, 8'hB2, 8'hA1});
        wait_serial_complete();
        repeat(5) @(posedge clk);

        // ========== Test Case 3: 2通道测试 ==========
        test_case = 3;
        $display("\n[Test Case %0d] 2 Channels Enabled", test_case);
        config_gating(0);  // gate_en=0 -> 2通道
        data_serial_ready = 1;
        
        // 发送数据，只有低2个通道有效
        send_parallel_data({8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'h99, 8'h55});
        wait_serial_complete();
        repeat(5) @(posedge clk);

        // ========== Test Case 4: 背压测试 ==========
        test_case = 4;
        $display("\n[Test Case %0d] Backpressure Test", test_case);
        config_gating(2);  // 8通道
        data_serial_ready = 0;  // 开始时不就绪
        
        // 发送数据
        send_parallel_data({8'h08, 8'h07, 8'h06, 8'h05, 8'h04, 8'h03, 8'h02, 8'h01});
        
        // 等待几个周期
        repeat(3) @(posedge clk);
        
        // 随机背压：间歇性拉高ready
        repeat(20) begin
            @(posedge clk);
            data_serial_ready <= ($random & 1);
        end
        
        // 恢复持续就绪
        data_serial_ready = 1;
        wait_serial_complete();
        repeat(5) @(posedge clk);

        // ========== Test Case 5: 连续发送 ==========
        test_case = 5;
        $display("\n[Test Case %0d] Continuous Send", test_case);
        config_gating(2);
        data_serial_ready = 1;
        
        $display("--- First batch ---");
        send_parallel_data({8'hFF, 8'hEE, 8'hDD, 8'hCC, 8'hBB, 8'hAA, 8'h99, 8'h88});
        wait_serial_complete();
        
        $display("--- Second batch ---");
        send_parallel_data({8'h00, 8'h11, 8'h22, 8'h33, 8'h44, 8'h55, 8'h66, 8'h77});
        wait_serial_complete();
        
        repeat(5) @(posedge clk);

        // ========== Test Case 6: 状态标志测试 ==========
        test_case = 6;
        $display("\n[Test Case %0d] Status Flag Test", test_case);
        config_gating(1);  // 4通道
        data_serial_ready = 0;  // 下游不就绪
        
        // 发送数据
        send_parallel_data({8'hAA, 8'hBB, 8'hCC, 8'hDD, 8'h11, 8'h22, 8'h33, 8'h44});
        repeat(2) @(posedge clk);
        
        // 检查full标志
        if (mem_full && !mem_empty) begin
            $display("✓ Status correct after loading: full=1, empty=0");
        end else begin
            $display("✗ Status error after loading: full=%b, empty=%b", mem_full, mem_empty);
            errors = errors + 1;
        end
        
        // 开始读取
        data_serial_ready = 1;
        wait_serial_complete();
        repeat(2) @(posedge clk);
        
        // 检查empty标志
        if (!mem_full && mem_empty) begin
            $display("✓ Status correct after reading: full=0, empty=1");
        end else begin
            $display("✗ Status error after reading: full=%b, empty=%b", mem_full, mem_empty);
            errors = errors + 1;
        end

        // ========== 测试结束 ==========
        $display("\n========================================");
        $display("  Test Summary:");
        $display("  Parallel Data Sent: %0d", data_sent);
        $display("  Serial Data Received: %0d", data_received);
        $display("  Passed: %0d", passed);
        $display("  Errors: %0d", errors);
        if (errors == 0) begin
            $display("  Status: ✓ ALL TESTS PASSED!");
        end else begin
            $display("  Status: ✗ SOME TESTS FAILED!");
        end
        $display("========================================");
        
        repeat(10) @(posedge clk);
        $finish;
    end

    // ========== 超时保护 ==========
    initial begin
        #10000;
        $display("\n[%0t] ERROR: Simulation Timeout!", $time);
        $finish;
    end

    // ========== 波形记录 ==========
    initial begin
        $dumpfile("tb_Cache.vcd");
        $dumpvars(0, tb_Cache);
    end

endmodule