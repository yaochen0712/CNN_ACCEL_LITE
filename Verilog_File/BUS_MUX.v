module BUS_MUX 
#(
    parameter D_WIDTH = 8
)
(
    inout [D_WIDTH-1:0] data_a,
    inout valid_a,
    inout ready_a,

    inout [D_WIDTH-1:0] data_b_0,
    inout valid_b_0,
    inout ready_b_0,

    inout [D_WIDTH-1:0] data_b_1,
    inout valid_b_1,
    inout ready_b_1,

    input sel
);
    assign data_a = sel ? data_b_1 : data_b_0;
    assign valid_a = sel ? valid_b_1 : valid_b_0;
    assign ready_a = sel ? ready_b_1 : ready_b_0;
endmodule