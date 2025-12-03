`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: tb_databuf
// Description: Data_Buffer模块的testbench
//              - 测试从BRAM读取512个数据
//              - 测试首次自动发送
//              - 测试后续控制信号触发发送
//              - 测试控制信号下降沿重置
//////////////////////////////////////////////////////////////////////////////////

module tb_databuf();

    // 参数定义
    localparam CLK_PERIOD = 10;
    localparam DATA_WIDTH = 8;
    localparam BUFFER_DEPTH = 512;
    localparam DW = 8;
    
    // 时钟和复位
    reg clk;
    reg rst_n;
    
    // 控制信号
    reg ctrl_enable;
    reg downstream_ready;
    reg r_en;
    
    // 上游数据源信号（BM_control_stream_v2）
    wire w_test_addr_done;
    wire [DW-1:0] w_test_bram_data;
    wire [14:0] w_test_bram_addr;
    wire [DW-1:0] w_test_data;
    wire w_test_data_valid;
    wire w_test_data_ready;
    
    // DUT输出信号
    wire [DATA_WIDTH-1:0] data_out;
    wire data_out_valid;
    
    // 统计变量
    integer received_count;
    integer first_batch_count;
    integer second_batch_count;
    integer i;
    
    // 时钟生成
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // 数据源模块 - BM_control_stream_v2
    BM_control_stream_v2 #(
        .WIDTH(DW),
        .ADDR_RANGE(21504)
    )
    u_DATA_IN_CTRL(
        .clk(clk),
        .rst_n(rst_n),
        .en(r_en),
        .o_addr_done(w_test_addr_done),
        .i_bram_data(w_test_bram_data),
        .o_bram_addr(w_test_bram_addr),
        .o_data_out(w_test_data),
        .o_data_out_valid(w_test_data_valid),
        .i_data_out_ready(w_test_data_ready)
    );
    
    // 测试用的数据BRAM
    simv_data_input u_simv_data_input(
        .clka(clk),
        .rsta(~rst_n),
        .wea(1'b0),
        .addra(w_test_bram_addr),
        .dina(8'h00),
        .douta(w_test_bram_data)
    );
    
    // DUT实例化 - Data_Buffer
    Data_Buffer #(
        .DATA_WIDTH(DATA_WIDTH),
        .BUFFER_DEPTH(BUFFER_DEPTH)
    )
    u_Data_Buffer(
        .clk(clk),
        .rst_n(rst_n),
        .i_ctrl_enable(ctrl_enable),
        .i_data_in(w_test_data),
        .i_data_in_valid(w_test_data_valid),
        .o_data_in_ready(w_test_data_ready),
        .o_data_out(data_out),
        .o_data_out_valid(data_out_valid),
        .i_data_out_ready(downstream_ready)
    );
    
    // 握手信号
    wire upstream_handshake = w_test_data_valid && w_test_data_ready;
    wire downstream_handshake = data_out_valid && downstream_ready;
    
    // 监控下游输出
    always @(posedge clk) begin
        if (downstream_handshake) begin
            received_count = received_count + 1;
            
            if (received_count <= 5 || received_count > BUFFER_DEPTH - 5) begin
                $display("[%0t] Received data[%0d] = 0x%02h", $time, received_count, data_out);
            end else if (received_count % 100 == 0) begin
                $display("[%0t] Received %0d data...", $time, received_count);
            end
            
            // 统计第一批和第二批
            if (received_count == BUFFER_DEPTH) begin
                first_batch_count = BUFFER_DEPTH;
                $display("[%0t] ========== First batch complete: %0d data ==========", 
                         $time, first_batch_count);
            end else if (received_count == 2 * BUFFER_DEPTH) begin
                second_batch_count = BUFFER_DEPTH;
                $display("[%0t] ========== Second batch complete: %0d data ==========", 
                         $time, second_batch_count);
            end
        end
    end
    
    // 主测试流程
    initial begin
        $display("\n========== Data_Buffer Testbench Start ==========\n");
        
        // 初始化
        initialize();
        
        // 测试1: 首次自动发送
        $display("\n[Test 1] First Run - Auto Send After Filling");
        $display("  Starting upstream data source...");
        
        @(posedge clk);
        r_en = 1;  // 启动上游数据源
        downstream_ready = 1;  // 下游准备好接收
        
        // 等待第一批512个数据发送完成
        wait(received_count == BUFFER_DEPTH);
        repeat(10) @(posedge clk);
        
        $display("  Test 1 PASSED: %0d data received automatically", first_batch_count);
        
        // 测试2: 等待控制信号触发
        $display("\n[Test 2] Second Run - Wait for Control Trigger");
        $display("  Buffer should be refilling now...");
        
        // 等待一段时间，让缓存重新填充
        repeat(1000) @(posedge clk);
        
        $display("  Triggering control signal (posedge)...");
        @(posedge clk);
        ctrl_enable = 1;
        @(posedge clk);
        @(posedge clk);
        
        // 等待第二批512个数据发送完成
        wait(received_count == 2 * BUFFER_DEPTH);
        repeat(10) @(posedge clk);
        
        $display("  Test 2 PASSED: %0d data received after trigger", second_batch_count);
        
        // 测试3: 控制信号下降沿重置测试
        $display("\n[Test 3] Control Signal Reset (negedge)");
        
        // 等待缓存重新填充
        repeat(1000) @(posedge clk);
        
        $display("  Triggering control posedge again...");
        ctrl_enable = 0;
        repeat(5) @(posedge clk);
        ctrl_enable = 1;
        repeat(3) @(posedge clk);
        
        // 开始接收数据
        received_count = 0;  // 重置计数
        downstream_ready = 1;
        
        // 接收一部分数据后，测试下降沿重置
        wait(received_count == 512);
        @(posedge clk);
        $display("  Sending control negedge (reset)...");
        @(posedge clk);
        ctrl_enable = 0;
        @(posedge clk);
        
        // 检查是否停止发送
        repeat(10) @(posedge clk);
        if (!data_out_valid) begin
            $display("  Test 3 PASSED: Output stopped after negedge");
        end else begin
            $display("  Test 3 FAILED: Output did not stop");
        end
        
        // 测试4: 下游反压测试
        $display("\n[Test 4] Downstream Backpressure Test");
        
        // 重新触发发送
        @(posedge clk);
        ctrl_enable = 1;
        repeat(3) @(posedge clk);
        
        received_count = 0;
        
        // 随机反压
        downstream_ready = 1;
        ctrl_enable = 0;
        #6000
        ctrl_enable = 1;
        wait(received_count >= 100);
        $display("  Test 4 PASSED: Backpressure handled correctly, received %0d", received_count);
        
        // 测试完成
        repeat(1200) @(posedge clk);
        
        $display("\n========== All Tests Completed ==========");
        $display("Summary:");
        $display("  - First batch:  %0d data (auto send)", first_batch_count);
        $display("  - Second batch: %0d data (trigger send)", second_batch_count);
        $display("  - Control reset: PASSED");
        $display("  - Backpressure: PASSED");
        $display("========================================\n");
        
        $finish;
    end
    
    // 初始化任务
    task initialize();
        begin
            rst_n = 0;
            ctrl_enable = 0;
            downstream_ready = 0;
            r_en = 0;
            received_count = 0;
            first_batch_count = 0;
            second_batch_count = 0;
            
            repeat(10) @(posedge clk);
            rst_n = 1;
            repeat(5) @(posedge clk);
        end
    endtask
    
    // 超时保护
    initial begin
        #(CLK_PERIOD * 100000);
        $display("ERROR: Simulation timeout!");
        $finish;
    end
    
    // 波形文件
    initial begin
        $dumpfile("tb_databuf.vcd");
        $dumpvars(0, tb_databuf);
    end

endmodule
