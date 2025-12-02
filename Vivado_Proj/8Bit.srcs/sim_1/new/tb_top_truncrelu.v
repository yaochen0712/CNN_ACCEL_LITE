`timescale 1ns / 1ps

module tb_top_truncrelu();

    // 参数定义
    localparam CHANNEL = 2;
    localparam D_IWIDTH = 24;
    localparam D_OWIDTH = 8;
    localparam CLK_PERIOD = 10;
    
    // 信号声明
    reg clk;
    reg rst_n;
    reg [D_IWIDTH*CHANNEL-1:0] i_data_in;
    reg i_data_in_valid;
    wire o_data_in_ready;
    wire [D_OWIDTH*CHANNEL-1:0] o_data_out;
    wire o_data_out_valid;
    reg i_data_out_ready;
    
    // 配置信号
    reg i_cfg_en;
    reg [$clog2(D_IWIDTH-D_OWIDTH)-1:0] i_trunction_cfg_lsb_index;
    reg i_trunction_cfg_saturate_en;
    reg i_relu_en;
    
    // 测试用变量
    integer test_case;
    integer data_count;
    integer sent_count;
    integer received_count;
    reg [D_IWIDTH-1:0] test_data_queue [0:999]; // 数据队列
    reg test_active;
    integer block_count; // 阻塞计数器
    
    // DUT实例化
    top_multi_relu_trunc #(
        .CHANNEL(CHANNEL),
        .D_IWIDTH(D_IWIDTH),
        .D_OWIDTH(D_OWIDTH)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .i_data_in(i_data_in),
        .i_data_in_valid(i_data_in_valid),
        .o_data_in_ready(o_data_in_ready),
        .o_data_out(o_data_out),
        .o_data_out_valid(o_data_out_valid),
        .i_data_out_ready(i_data_out_ready),
        .i_cfg_en(i_cfg_en),
        .i_trunction_cfg_lsb_index(i_trunction_cfg_lsb_index),
        .i_trunction_cfg_saturate_en(i_trunction_cfg_saturate_en),
        .i_relu_en(i_relu_en)
    );
    
    // 时钟生成
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // 主测试流程
    initial begin
        $display("========== Starting Pipeline Stress Test for top_multi_relu_trunc ==========");
        
        // 初始化
        initialize();
        
        // 测试用例1: 基本截位流水线测试 - LSB=0 (取低8位)
        test_case = 1;
        $display("\n[Test%0d] LSB=0, ReLU=OFF, Saturation=OFF - Pipeline Stress Test", test_case);
        configure_module(0, 0, 0);  // lsb=0, relu=off, saturate=off
        pipeline_stress_test(50, 0); // 50个数据包，基本截位测试数据
        
        // 测试用例2: LSB=8 (取中间8位) 流水线测试
        test_case = 2;
        $display("\n[Test%0d] LSB=8, ReLU=OFF, Saturation=OFF - Pipeline Stress Test", test_case);
        configure_module(8, 0, 0);  // lsb=8, relu=off, saturate=off
        pipeline_stress_test(50, 0); // 50个数据包，中间位测试数据
        
        // 测试用例3: LSB=16 (取高8位) 流水线测试
        test_case = 3;
        $display("\n[Test%0d] LSB=16, ReLU=OFF, Saturation=OFF - Pipeline Stress Test", test_case);
        configure_module(16, 0, 0); // lsb=16, relu=off, saturate=off
        pipeline_stress_test(50, 0); // 50个数据包，高位测试数据
        
        // 测试用例4: ReLU功能流水线测试
        test_case = 4;
        $display("\n[Test%0d] LSB=0, ReLU=ON, Saturation=OFF - Pipeline Stress Test", test_case);
        configure_module(0, 1, 0);  // lsb=0, relu=on, saturate=off
        pipeline_stress_test(80, 1); // 80个数据包，包含正负数
        
        // 测试用例5: 饱和功能流水线测试
        test_case = 5;
        $display("\n[Test%0d] LSB=0, ReLU=OFF, Saturation=ON - Pipeline Stress Test", test_case);
        configure_module(0, 0, 1);  // lsb=0, relu=off, saturate=on
        pipeline_stress_test(60, 2); // 60个数据包，大数值测试
        
        // 测试用例6: 组合功能流水线测试
        test_case = 6;
        $display("\n[Test%0d] LSB=8, ReLU=ON, Saturation=ON - Pipeline Stress Test", test_case);
        configure_module(8, 1, 1);  // lsb=8, relu=on, saturate=on
        pipeline_stress_test(100, 3); // 100个数据包，组合功能测试
        
        // 测试用例7: 反压流水线测试
        test_case = 7;
        $display("\n[Test%0d] Backpressure Pipeline Test", test_case);
        configure_module(0, 0, 0);
        pipeline_backpressure_test(80); // 80个数据包，随机反压
        
        // 测试用例8: 极限压力测试
        test_case = 8;
        $display("\n[Test%0d] Maximum Stress Test - 500 Continuous Data", test_case);
        configure_module(8, 1, 1); // 中间位+ReLU+饱和
        pipeline_stress_test(500, 1);
        
        $display("\n========== Pipeline Test Completed ==========");
        $display("Total Sent: %0d, Total Received: %0d", sent_count, received_count);
        $finish;
    end
    
    // 初始化任务
    task initialize();
        begin
            rst_n = 0;
            i_data_in = 0;
            i_data_in_valid = 0;
            i_data_out_ready = 1;
            i_cfg_en = 0;
            i_trunction_cfg_lsb_index = 0;
            i_trunction_cfg_saturate_en = 0;
            i_relu_en = 0;
            test_case = 0;
            data_count = 0;
            sent_count = 0;
            received_count = 0;
            test_active = 0;
            
            #(CLK_PERIOD * 5);
            rst_n = 1;
            #(CLK_PERIOD * 2);
        end
    endtask
    
    // 配置模块
    task configure_module(
        input [$clog2(D_IWIDTH-D_OWIDTH)-1:0] lsb_idx,
        input relu_enable,
        input saturate_enable
    );
        begin
            @(posedge clk);
            i_cfg_en = 1;
            i_trunction_cfg_lsb_index = lsb_idx;
            i_relu_en = relu_enable;
            i_trunction_cfg_saturate_en = saturate_enable;
            @(posedge clk);
            i_cfg_en = 0;
            #(CLK_PERIOD * 2); // 等待配置生效
        end
    endtask
    
    // 生成测试数据
    task generate_test_data(input integer count, input integer test_type);
        integer i;
        begin
            for (i = 0; i < count; i = i + 1) begin
                case (test_type)
                    0: begin // 基本递增数据
                        test_data_queue[i*2] = i * 'h1000 + 'h123456;
                        test_data_queue[i*2+1] = i * 'h2000 + 'h789ABC;
                    end
                    1: begin // 随机正负数（ReLU测试）
                        if (i % 4 == 0) begin
                            test_data_queue[i*2] = $random & 24'h7FFFFF; // 正数
                            test_data_queue[i*2+1] = $random | 24'h800000; // 负数
                        end else if (i % 4 == 1) begin
                            test_data_queue[i*2] = $random | 24'h800000; // 负数
                            test_data_queue[i*2+1] = $random & 24'h7FFFFF; // 正数
                        end else begin
                            test_data_queue[i*2] = $random;
                            test_data_queue[i*2+1] = $random;
                        end
                    end
                    2: begin // 大数值（饱和测试）
                        test_data_queue[i*2] = $random + 24'h100000;
                        test_data_queue[i*2+1] = $random + 24'h200000;
                    end
                    3: begin // 组合测试数据
                        test_data_queue[i*2] = $random;
                        test_data_queue[i*2+1] = $random;
                    end
                    default: begin
                        test_data_queue[i*2] = i;
                        test_data_queue[i*2+1] = i + 'h800000;
                    end
                endcase
            end
        end
    endtask
    
    // 流水线压力测试
    task pipeline_stress_test(input integer count, input integer test_type);
        integer i;
        begin
            $display("  Starting to send %0d continuous data packets...", count);
            generate_test_data(count, test_type);
            
            test_active = 1;
            sent_count = 0;
            i_data_out_ready = 1; // 下游始终就绪
            
            // 连续发送数据，valid始终拉高
            for (i = 0; i < count; i = i + 1) begin
                @(posedge clk);
                
                // 更新数据
                i_data_in = {test_data_queue[i*2+1], test_data_queue[i*2]};
                i_data_in_valid = 1;
                
                // 等待握手成功
                while (!o_data_in_ready) @(posedge clk);
                
                sent_count = sent_count + 1;
                if (sent_count % 20 == 0) begin
                    $display("    Sent: %0d/%0d", sent_count, count);
                end
            end
            
            // 发送完成，拉低valid
            @(posedge clk);
            i_data_in_valid = 0;
            
            // 等待所有数据输出
            while (received_count < sent_count) begin
                @(posedge clk);
            end
            
            test_active = 0;
            $display("  Stress test completed: Sent %0d, Received %0d", sent_count, received_count);
            #(CLK_PERIOD * 10); // 稳定时间
        end
    endtask
    
    // 带反压的流水线测试
    task pipeline_backpressure_test(input integer count);
        integer i;
        reg [1:0] ready_pattern;
        begin
            $display("  Starting backpressure test, sending %0d data packets...", count);
            generate_test_data(count, 1);
            
            test_active = 1;
            sent_count = 0;
            ready_pattern = 0;
            
            fork
                // 数据发送进程 - valid持续拉高
                begin
                    for (i = 0; i < count; i = i + 1) begin
                        @(posedge clk);
                        i_data_in = {test_data_queue[i*2+1], test_data_queue[i*2]};
                        i_data_in_valid = 1;
                        
                        while (!o_data_in_ready) @(posedge clk);
                        sent_count = sent_count + 1;
                    end
                    @(posedge clk);
                    i_data_in_valid = 0;
                end
                
                // 反压控制进程 - 随机ready信号
                begin
                    while (sent_count < count || received_count < count) begin
                        @(posedge clk);
                        ready_pattern = ready_pattern + 1;
                        // 75%概率ready=1, 25%概率ready=0
                        i_data_out_ready = (ready_pattern != 2'b00);
                    end
                end
            join
            
            test_active = 0;
            $display("  Backpressure test completed: Sent %0d, Received %0d", sent_count, received_count);
            #(CLK_PERIOD * 10);
        end
    endtask
    
    // 输出数据监控进程
    always @(posedge clk) begin
        if (o_data_out_valid && i_data_out_ready) begin
            received_count = received_count + 1;
            
            // 详细输出（仅前几个和最后几个）
            if (received_count <= 5 || received_count > sent_count - 5) begin
                $display("    [%0d] Output: CH0=0x%02h(%0d), CH1=0x%02h(%0d)", 
                         received_count,
                         o_data_out[7:0], $signed(o_data_out[7:0]), 
                         o_data_out[15:8], $signed(o_data_out[15:8]));
            end else if (received_count % 50 == 0) begin
                $display("    Received: %0d", received_count);
            end
        end
    end
    
    // 性能统计
    real throughput;
    integer start_time, end_time;
    
    always @(posedge test_active) begin
        start_time = $time;
        received_count = 0;
    end
    
    always @(negedge test_active) begin
        end_time = $time;
        if (received_count > 0) begin
            throughput = (received_count * 1000.0) / (end_time - start_time); // 单位: 数据包/ns
            $display("  Performance Stats: %.2f packets/ns, Average Latency: %.1f ns", 
                     throughput, (end_time - start_time) * 1.0 / received_count);
        end
    end
    
    // 错误检测
    always @(posedge clk) begin
        if (i_data_in_valid && !o_data_in_ready && test_active) begin
            // 检测握手阻塞时间
            block_count = block_count + 1;
            if (block_count > 100) begin
                $display("WARNING: Handshake blocked for more than 100 cycles!");
                block_count = 0;
            end
        end else begin
            block_count = 0;
        end
    end
    
    // 超时保护
    initial begin
        #(CLK_PERIOD * 50000); // 50000个时钟周期超时
        $display("ERROR: Simulation timeout!");
        $finish;
    end

endmodule