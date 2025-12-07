module BUS_MUX_A //一进到多出
#(
    parameter D_WIDTH = 8
)
(
    // A侧：输入
    input   [D_WIDTH-1:0] data_a,
    input   valid_a,
    output  ready_a,

    // B0侧：输出
    output  [D_WIDTH-1:0] data_b_0,
    output  valid_b_0,
    input   ready_b_0,

    // B1侧：输出
    output  [D_WIDTH-1:0] data_b_1,
    output  valid_b_1,
    input   ready_b_1,

    input sel
);
    // 数据和valid从A侧分发到选中的B侧
    assign data_b_0 = data_a;
    assign data_b_1 = data_a;
    assign valid_b_0 = sel ? 1'b0 : valid_a;  // sel=0时，B0有效
    assign valid_b_1 = sel ? valid_a : 1'b0;  // sel=1时，B1有效
    
    // ready从选中的B侧反馈到A侧
    assign ready_a = sel ? ready_b_1 : ready_b_0;
endmodule



module BUS_MUX_B //多进选一出
#(
    parameter D_WIDTH = 8
)
(
    // A侧：输出
    output  [D_WIDTH-1:0] data_a,
    output  valid_a,
    input   ready_a,

    // B0侧：输入
    input   [D_WIDTH-1:0] data_b_0,
    input   valid_b_0,
    output  ready_b_0,

    // B1侧：输入
    input   [D_WIDTH-1:0] data_b_1,
    input   valid_b_1,
    output  ready_b_1,

    input sel
);
    // 从B侧选一路输出到A侧
    assign data_a = sel ? data_b_1 : data_b_0;
    assign valid_a = sel ? valid_b_1 : valid_b_0;
    
    // ready从A侧分配到选中的B侧
    assign ready_b_0 = sel ? 1'b0 : ready_a;  // sel=0时，B0接收ready
    assign ready_b_1 = sel ? ready_a : 1'b0;  // sel=1时，B1接收ready
endmodule

