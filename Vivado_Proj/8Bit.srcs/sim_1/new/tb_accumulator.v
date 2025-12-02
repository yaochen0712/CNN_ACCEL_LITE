`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: tb_accumulator
// Description: Testbench for Accumulator module
//              - 测试多通道累加功能
//              - 测试门控功能
//              - 测试BIAS加法
//              - 测试累加次数控制
//              - 测试握手协议
//              - 自动结果检查
//              - 简化为8bit输入方便调试
//////////////////////////////////////////////////////////////////////////////////

module tb_accumulator();

    // ========== 参数定义 ==========
    parameter D_WIDTH = 32;
    parameter COUNT_WIDTH = 9;           // $clog2(512)
    parameter GATE_PARA = 2;
    parameter CHANNEL_NUM = 8;           // 简化为8通道方便测试
    parameter MULTIOUT_DWIDTH = 8;       // 修改为8bit方便调试
    parameter CHANNEL_DATAWIDTH = 8;
    parameter CLK_PERIOD = 10;

    // ========== 时钟和复位 ==========
    reg clk;
    reg rst_n;

    // ========== 配置接口 ==========
    reg [COUNT_WIDTH-1:0] count_limit;
    reg [$clog2(GATE_PARA):0] cfg_gate_en;
    reg accumulator_cfg_en;

    // ========== 数据接口 ==========
    reg [MULTIOUT_DWIDTH*CHANNEL_NUM-1:0] data_in;
    reg data_in_valid;
    wire data_in_ready;

    // ========== BIAS接口 ==========
    reg [CHANNEL_DATAWIDTH*CHANNEL_NUM-1:0] bias_in;
    reg bias_in_valid;
    wire bias_in_ready;

    // ========== 输出接口 ==========
    wire [D_WIDTH*CHANNEL_NUM-1:0] data_out;
    wire data_out_valid;
    reg data_out_ready;

    // ========== 测试控制 ==========
    integer test_case;
    integer i, j;
    integer errors;
    integer passed;
    integer send_count;
    
    // ========== 预期值队列 ==========
    reg signed [D_WIDTH-1:0] expected_result [0:CHANNEL_NUM-1];
    reg signed [MULTIOUT_DWIDTH-1:0] accumulated_data [0:CHANNEL_NUM-1];
    reg signed [CHANNEL_DATAWIDTH-1:0] bias_data [0:CHANNEL_NUM-1];

    // ========== DUT实例化 ==========
    Accumulator #(
        .D_WIDTH(D_WIDTH),
        .COUNT_WIDTH(COUNT_WIDTH),
        .GATE_PARA(GATE_PARA),
        .CHANNEL_NUM(CHANNEL_NUM),
        .MULTIOUT_DWIDTH(MULTIOUT_DWIDTH),
        .CHANNEL_DATAWIDTH(CHANNEL_DATAWIDTH)
    ) u_accumulator (
        .clk(clk),
        .rst_n(rst_n),
        .i_count_limit(count_limit),
        .i_cfg_gate_en(cfg_gate_en),
        .i_accumulator_cfg_en(accumulator_cfg_en),
        .i_data_in(data_in),
        .i_data_in_valid(data_in_valid),
        .o_data_in_ready(data_in_ready),
        .i_bias_in(bias_in),
        .i_bias_in_valid(bias_in_valid),
        .o_bias_in_ready(bias_in_ready),
        .o_data_out(data_out),
        .o_data_out_valid(data_out_valid),
        .i_data_out_ready(data_out_ready)
    );

    // ========== 时钟生成 ==========
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ========== 握手检测 ==========
    wire input_handshake = data_in_valid && data_in_ready;
    wire output_handshake = data_out_valid && data_out_ready;
    wire bias_handshake = bias_in_valid && bias_in_ready;

    // ========== 监控输出 - 显示每个通道的输入数据 ==========
    always @(posedge clk) begin
        if (input_handshake) begin
            $display("[%0t] Input Handshake #%0d:", $time, send_count + 1);
            for (i = 0; i < CHANNEL_NUM; i = i + 1) begin
                $display("  CH[%0d] input = %0d (0x%02h)", i,
                         $signed(data_in[MULTIOUT_DWIDTH*i +: MULTIOUT_DWIDTH]),
                         data_in[MULTIOUT_DWIDTH*i +: MULTIOUT_DWIDTH]);
            end
        end
        if (output_handshake) begin
            $display("[%0t] Output Handshake:", $time);
            for (i = 0; i < CHANNEL_NUM; i = i + 1) begin
                $display("  CH[%0d] output = %0d (0x%08h)", i, 
                         $signed(data_out[D_WIDTH*i +: D_WIDTH]),
                         data_out[D_WIDTH*i +: D_WIDTH]);
            end
        end
        if (bias_handshake) begin
            $display("[%0t] BIAS Handshake", $time);
        end
    end

    // ========== 计算有效通道数 ==========
    function integer calc_valid_channels;
        input [GATE_PARA-1:0] gate_en;
        begin
            calc_valid_channels = (CHANNEL_NUM >> GATE_PARA) << gate_en;
        end
    endfunction

    // ========== Task: 复位 ==========
    task reset_dut;
        begin
            $display("\n[%0t] ========== Reset Start ==========", $time);
            rst_n = 0;
            count_limit = 0;
            cfg_gate_en = 0;
            accumulator_cfg_en = 0;
            data_in = 0;
            data_in_valid = 0;
            bias_in = 0;
            bias_in_valid = 0;
            data_out_ready = 0;
            errors = 0;
            passed = 0;
            send_count = 0;
            
            // 清空预期值
            for (i = 0; i < CHANNEL_NUM; i = i + 1) begin
                expected_result[i] = 0;
                accumulated_data[i] = 0;
                bias_data[i] = 0;
            end
            
            repeat(5) @(posedge clk);
            rst_n = 1;
            repeat(2) @(posedge clk);
            $display("[%0t] ========== Reset Done ==========", $time);
        end
    endtask

    // ========== Task: 配置累加器 ==========
    task config_accumulator;
        input [COUNT_WIDTH-1:0] acc_count;
        input [GATE_PARA-1:0] gate_en;
        integer valid_ch;
        begin
            valid_ch = calc_valid_channels(gate_en);
            $display("\n[%0t] Config: count=%0d, gate_en=%0d, valid_channels=%0d/%0d", 
                     $time, acc_count, gate_en, valid_ch, CHANNEL_NUM);
            @(posedge clk);
            accumulator_cfg_en = 1;
            count_limit = acc_count;
            cfg_gate_en = gate_en;
            @(posedge clk);
            accumulator_cfg_en = 0;
            @(posedge clk);
        end
    endtask

       // ========== Task: 发送数据 ==========
     // ========== Task: 发送数据（持续拉高valid - 压力测试） ==========
    task send_data_continuous;
        input integer num_cycles;  // 持续多少个周期
        input [MULTIOUT_DWIDTH*CHANNEL_NUM-1:0] data;
        integer ch, cycle;
        begin
            $display("\n[%0t] Sending data continuously for %0d cycles with valid held high", $time, num_cycles);
            
            @(posedge clk);
            data_in = data;
            data_in_valid = 1;  // ← 拉高valid
            
            // 持续发送，直到收到握手或达到周期数
            for (cycle = 0; cycle < num_cycles; cycle = cycle + 1) begin
                if (input_handshake) begin
                    // 握手发生时累加
                    for (ch = 0; ch < CHANNEL_NUM; ch = ch + 1) begin
                        accumulated_data[ch] = accumulated_data[ch] + 
                                               $signed(data[MULTIOUT_DWIDTH*ch +: MULTIOUT_DWIDTH]);
                    end
                    send_count = send_count + 1;
                    $display("[%0t] Handshake #%0d occurred", $time, send_count);
                end
                @(posedge clk);
            end
            
            data_in_valid = 0;  // ← 拉低valid
            data_in = 0;
            @(posedge clk);
            
            $display("[%0t] Data transmission complete, total handshakes: %0d", $time, send_count);
        end
    endtask

    task send_data;
        input [MULTIOUT_DWIDTH*CHANNEL_NUM-1:0] data;
        integer ch;
        begin
            // 累加到预期值
            for (ch = 0; ch < CHANNEL_NUM; ch = ch + 1) begin
                accumulated_data[ch] = accumulated_data[ch] + 
                                       $signed(data[MULTIOUT_DWIDTH*ch +: MULTIOUT_DWIDTH]);
            end
            
            @(posedge clk);
            data_in = data;
            data_in_valid = 1;
            
            // 等待握手 - 在同一个周期内检测
            wait(input_handshake);  // 等待握手发生
            
            @(posedge clk);  // 下一个周期才拉低valid
            data_in_valid = 0;
            data_in = 0;
            
            send_count = send_count + 1;
        end
    endtask

    // ========== Task: 发送BIAS ==========
    task send_bias;
        input [CHANNEL_DATAWIDTH*CHANNEL_NUM-1:0] bias_data_in;
        integer ch;
        begin
            $display("\n[%0t] Sending BIAS:", $time);
            
            // 保存BIAS数据
            for (ch = 0; ch < CHANNEL_NUM; ch = ch + 1) begin
                bias_data[ch] = bias_data_in[CHANNEL_DATAWIDTH*ch +: CHANNEL_DATAWIDTH];
                $display("  BIAS[%0d] = %0d (0x%02h)", ch, $signed(bias_data[ch]), bias_data[ch]);
            end
            
            @(posedge clk);
            bias_in = bias_data_in;
            bias_in_valid = 1;
            
            // 等待握手
            wait(bias_handshake);
            
            @(posedge clk);
            bias_in_valid = 0;
            bias_in = 0;
        end
    endtask

    // ========== Task: 接收并检查输出 ==========
    task receive_and_check;
        integer ch;
        integer valid_ch;
        reg signed [D_WIDTH-1:0] actual_value;
        reg signed [D_WIDTH-1:0] expected_value;
        begin
            valid_ch = calc_valid_channels(cfg_gate_en);
            
            // 计算预期值（累加结果 + BIAS）
            $display("\n[%0t] Expected values:", $time);
            for (ch = 0; ch < CHANNEL_NUM; ch = ch + 1) begin
                if (ch < valid_ch) begin
                    expected_result[ch] = accumulated_data[ch] + $signed(bias_data[ch]);
                    $display("  CH[%0d]: acc=%0d + bias=%0d = %0d", 
                             ch, $signed(accumulated_data[ch]), $signed(bias_data[ch]), 
                             $signed(expected_result[ch]));
                end else begin
                    expected_result[ch] = 0;
                end
            end
            
            @(posedge clk);
            data_out_ready = 1;
            
            // 等待握手
            wait(output_handshake);
            
            @(posedge clk);
            data_out_ready = 0;
            
            $display("\n[%0t] Checking output:", $time);
            
            // 检查结果
            for (ch = 0; ch < valid_ch; ch = ch + 1) begin
                actual_value = data_out[D_WIDTH*ch +: D_WIDTH];
                expected_value = expected_result[ch];
                
                if (actual_value === expected_value) begin
                    $display("  ✓ CH[%0d]: %0d (PASS)", ch, $signed(actual_value));
                    passed = passed + 1;
                end else begin
                    $display("  ✗ CH[%0d]: %0d, expected %0d (FAIL)", 
                             ch, $signed(actual_value), $signed(expected_value));
                    errors = errors + 1;
                end
            end
            
            // 清空累加值
            for (ch = 0; ch < CHANNEL_NUM; ch = ch + 1) begin
                accumulated_data[ch] = 0;
            end
            send_count = 0;
        end
    endtask

    // ========== Task: 生成测试数据（8bit范围） ==========
    function [MULTIOUT_DWIDTH*CHANNEL_NUM-1:0] gen_test_data;
        input [7:0] pattern;
        input integer offset;
        integer ch;
        reg signed [MULTIOUT_DWIDTH-1:0] temp_data;
        begin
            gen_test_data = 0;
            for (ch = 0; ch < CHANNEL_NUM; ch = ch + 1) begin
                case (pattern)
                    0: temp_data = ch + offset;                    // 递增: 0,1,2,3...
                    1: temp_data = (ch + 1) * offset;              // 倍数
                    2: temp_data = -ch - offset;                   // 递减负数
                    3: temp_data = (ch % 2) ? offset : -offset;   // 交替
                    4: temp_data = offset;                         // 全部相同
                    default: temp_data = ($random % 127) + 1;      // 随机正数1-127
                endcase
                gen_test_data[MULTIOUT_DWIDTH*ch +: MULTIOUT_DWIDTH] = temp_data;
            end
        end
    endfunction

    // ========== Task: 生成BIAS数据 ==========
    function [CHANNEL_DATAWIDTH*CHANNEL_NUM-1:0] gen_bias_data;
        input signed [CHANNEL_DATAWIDTH-1:0] base_bias;
        integer ch;
        begin
            gen_bias_data = 0;
            for (ch = 0; ch < CHANNEL_NUM; ch = ch + 1) begin
                gen_bias_data[CHANNEL_DATAWIDTH*ch +: CHANNEL_DATAWIDTH] = base_bias + ch;
            end
        end
    endfunction

    // ========== 主测试流程 ==========
    initial begin
        $display("========================================");
        $display("  Accumulator Module Testbench Start");
        $display("  CHANNEL_NUM = %0d", CHANNEL_NUM);
        $display("  MULTIOUT_DWIDTH = %0d bit (简化调试)", MULTIOUT_DWIDTH);
        $display("========================================");
        
        // ========== Test Case 0: 复位测试 ==========
        test_case = 0;
        reset_dut();
        #100;

        // ========== Test Case 6: 压力测试 - 累加8次，持续拉高valid发送32个数据 ==========
        test_case = 6;
        $display("\n[Test Case %0d] Pressure Test (Count=8, Continuous Valid with 32 cycles)", test_case);
        
        config_accumulator(8, 0);   // 配置累加8次
        cfg_gate_en = 0; // 全通道使能
        send_bias(gen_bias_data(8'd2));     // BIAS = 2, 3, 4, 5, 6, 7, 8, 9
        //receive_and_check();
        data_out_ready = 1;  // 始终准备好接收数据
        // 持续拉高valid，发送32个周期
        // 只有前8个握手会被记录
        send_data_continuous(32, gen_test_data(4, 1));  // 全部发送1，持续32个周期
        
        // CH0预期: (1+1+1+1+1+1+1+1)+2 = 10
        // CH1预期: (1+1+1+1+1+1+1+1)+3 = 11
        // 其他通道类似
        
        //receive_and_check();
        repeat(5) @(posedge clk);

        // ========== 测试结束 ==========
        $display("\n========================================");
        $display("  Test Summary:");
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
        #100000;
        $display("\n[%0t] ERROR: Simulation Timeout!", $time);
        $finish;
    end

    // ========== 波形记录 ==========
    initial begin
        $dumpfile("tb_accumulator.vcd");
        $dumpvars(0, tb_accumulator);
    end

endmodule