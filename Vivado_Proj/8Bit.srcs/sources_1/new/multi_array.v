`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/09/28 09:24:28
// Design Name: 
// Module Name: multi_array
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: Multiplier array with complete handshake control
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module multi_array
#(
    parameter NUM_MULTS = 128,
    parameter DIN_WIDTH = 8,
    parameter WGT_WIDTH = 8,
    parameter DOUT_WIDTH = 16,
    parameter LATENCY = 3,  // Vivado mult_gen IP latency (3 cycles)
    parameter GATE_PARA = 1 //2则表示将所有的MULTS分成四组进行CLK GATING门控
)
(
    input clk,
    input rst_n,

    // o_error flag: data/weight valid mismatch
    output o_error,
    
    // BRAM data input port
    input [DIN_WIDTH*NUM_MULTS-1:0] i_bram_data_din,
    input i_bram_data_valid,
    output o_bram_data_ready,

    // BRAM weight input port
    input [WGT_WIDTH*NUM_MULTS-1:0] i_bram_weight_din,
    input i_bram_weight_valid,
    output o_bram_weight_ready,

    // Output
    output [DOUT_WIDTH*NUM_MULTS-1:0] o_data_out,
    output reg o_data_out_valid,
    input i_data_out_ready,

    //gating Control
    input i_cfg_valid,
    input [$clog2(GATE_PARA):0] i_gate_en
);
    wire weight_fire;
    assign weight_fire =i_bram_weight_valid & o_bram_weight_ready;
    wire input_fire;
    assign input_fire = i_bram_data_valid & o_bram_data_ready;
    wire data_out_fire;
    assign data_out_fire = o_data_out_valid & i_data_out_ready;
    wire all_in_fire;
    assign all_in_fire = weight_fire & input_fire;
    wire all_valid;
    assign all_valid = i_bram_data_valid & i_bram_weight_valid;

    reg [$clog2(GATE_PARA):0] gate_en_reg;
    always @(posedge clk)begin
        if(i_cfg_valid)begin
            gate_en_reg <= i_gate_en ;
        end
    end

    //ready 信号握手逻辑 此处为了同步采用等待上游valid就位的方式取巧
    reg ready_reg;
    assign o_bram_weight_ready = ready_reg;
    assign o_bram_data_ready = ready_reg;

    always @(posedge clk or negedge rst_n)begin
        if(~rst_n)begin
            ready_reg <= 0;
        end
        else if(all_valid & i_data_out_ready)begin
            ready_reg <= 1;
        end
        else begin
            ready_reg <= 0;
        end
    end

    //握手用作valid的延迟链
    integer i;
    reg valid_chain [LATENCY-1:0];
    always @(posedge clk or negedge rst_n)begin
        if(~rst_n)begin
            for(i=0;i<LATENCY;i=i+1)begin
                valid_chain[i]<=1'b0;
            end
        end 
        else begin
            valid_chain[LATENCY-1] <= all_valid;
            for(i=0;i<LATENCY-1;i=i+1)begin
                valid_chain[i]<=valid_chain[i+1];
            end
        end
    end


    always @(posedge clk or negedge rst_n)begin
        if(~rst_n)begin
            o_data_out_valid <= 0;
        end
        else if(i_data_out_ready)begin
            o_data_out_valid <= valid_chain[0];
        end
    end


    // ========== Input signal split and latch ==========
    reg [DIN_WIDTH-1:0] data_in [NUM_MULTS-1:0];
    reg [WGT_WIDTH-1:0] weight_in [NUM_MULTS-1:0];
    integer k;  // Loop variable declaration at module level
    // Latch input data when input_fire occurs
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (k = 0; k < NUM_MULTS; k = k+1) begin
                data_in[k] <= {DIN_WIDTH{1'b0}};
                weight_in[k] <= {WGT_WIDTH{1'b0}};
            end
        end else if (all_valid) begin
            for (k = 0; k < NUM_MULTS; k = k+1) begin
                data_in[k] <= i_bram_data_din[k*DIN_WIDTH +: DIN_WIDTH];
                weight_in[k] <= i_bram_weight_din[k*WGT_WIDTH +: WGT_WIDTH];
            end
        end
    end

    // ========== Output signal concatenation ==========
    wire [DOUT_WIDTH-1:0] mult_out [NUM_MULTS-1:0];
    genvar n;
    generate
        for(n = 0; n < NUM_MULTS; n = n+1) begin : output_concat
            assign o_data_out[n*DOUT_WIDTH +: DOUT_WIDTH] = mult_out[n];
        end
    endgenerate


    // 门控功能已移除，所有乘法器始终使能
    // ========== Multiplier array instantiation ==========
    generate
        for(n = 0; n < NUM_MULTS; n = n+1) begin : mult_inst
            mult_gen_0 mult_unit (
                .CLK(clk),
                .SCLR(~rst_n),
                .A(data_in[n]),
                .B(weight_in[n]),
                .P(mult_out[n]),
                .CE(1'b1) // 所有乘法器始终使能
            );
        end
    endgenerate

endmodule
