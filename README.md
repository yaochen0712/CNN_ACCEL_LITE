# FC_ACCEL_LITE

**电子科技大学 2025年秋季学期 ASIC设计 大实验项目与作业**  
Vivado 版本: <mark>2024.02 </mark>  
FIFO，BRAM，Mulitplier均是Xilinx/AMD的IP
  
## 系统架构 
 
```mermaid
graph TD
    A[Data from ps/FIFO] --> |8Bit| B[CHANNEL DATA MUX]
    C[Memory Cache] --> |8Bit| B
    B --> |8Bit| D[Parral Multiplier]
    D --> |16Bit * 128| E[Accumulator and Bias-adding]
    H[WEIGHT_BRAM_Controler] -->|8Bit * 128| D
    F[BIAS_BRAM_Controller] -->|8Bit * 128| E
    E --> |128 * 24bit| G[ReLu and Truncation]
    G --> |8Bit * 128| C
    G --> I[FeatureMap-Show]
    J[**Controller**] -.-> |Switch|B
    J -.-> |Channel_En|D
    J -.-> |Accumulate-Times| E
    J -.-> |ReLu-en and Truncation LSB|G
    E -.-> |layer_done|J
```  



### 系统特性:  

* 采用valid_ready的握手流程，支持反压。时序参照了AXI的握手部分可以兼容
* 可以用编写指令兼容更复杂的FC/CNN等
* 通道配置可以降低不必要的资源节省功耗，有较多复用结构
* 架构可扩展性好。比如可以加强Memorycache支持寻址可以配合多层同时计算等
* 可以通过配置宏，更改ASIC所支持的模型规模。同时Controler可以用简易控制命令编程


## 目前模块状态

|  模块名称  |   完成情况   |   具体说明   |
|:-----:|:----------:|:------:|
| ReLu和截位模块|测试通过||
|BIAS_BRAM_Controller|测试通过||
|乘法器|等待完善|两边不同步的输入握手尚未测试|
|缓存模块|测试通过||
|累加器和缓存|通过|Vivado仿真疑似BUG|



## Vivado 的奇怪行为
对比下面两个代码块
```
// 代码1
reg [CHANNEL_DATAWIDTH*CHANNEL_NUM-1:0] bias_buf;
    wire [CHANNEL_DATAWIDTH*CHANNEL_NUM-1:0] w_bias_buf;
    assign w_bias_buf = i_bias_in;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            bias_buf <= {(CHANNEL_DATAWIDTH*CHANNEL_NUM){1'b0}};
            o_bias_in_ready <= 1;
        end
        else if(bias_fire) begin
            bias_buf <= w_bias_buf;
            o_bias_in_ready <= 0;
        end
        else if(data_out_fire)begin
            o_bias_in_ready <= 1;
        end
    end

//代码2
reg [CHANNEL_DATAWIDTH*CHANNEL_NUM-1:0] bias_buf;
    wire [CHANNEL_DATAWIDTH*CHANNEL_NUM-1:0] w_bias_buf;
    assign w_bias_buf = i_bias_in;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            bias_buf <= {(CHANNEL_DATAWIDTH*CHANNEL_NUM){1'b0}};
            o_bias_in_ready <= 1;
        end
        else if(bias_fire) begin
            bias_buf <= i_bias_in;
            o_bias_in_ready <= 0;
        end
        else if(data_out_fire)begin
            o_bias_in_ready <= 1;
        end
    end

```  
代码1的能正常锁存但是代码2的不能锁存
![alt text](<屏幕截图 2025-11-10 160839.png>)
![alt text](<屏幕截图 2025-11-10 160936.png>)