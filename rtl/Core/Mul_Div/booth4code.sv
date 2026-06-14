timeunit 1ns;
timeprecision 1ps;
module booth4code #(
    parameter DATA_WIDTH = 32
)(
    input  logic [DATA_WIDTH-1:0] a_i,
    input  logic [2:0]            b_i,
    output logic [DATA_WIDTH+1:0] booth_o
);
always_comb begin
    case(b_i)
        3'b000 : booth_o = 0;//0
        3'b001,3'b010 : booth_o = {{2{a_i[DATA_WIDTH-1]}},a_i};//A
        3'b011 : booth_o =    {a_i[DATA_WIDTH-1],a_i,1'b0};//2A
        3'b100 : booth_o =  -({a_i[DATA_WIDTH-1],a_i,1'b0});//-2A
        3'b101,3'b110 : booth_o =  -{{2{a_i[DATA_WIDTH-1]}},a_i};//-A
        3'b111 : booth_o =  0;//0
        default: booth_o =  0;
    endcase
end



endmodule