timeunit 1ns;
timeprecision 1ps;
module pg_gen(
    input a,
    input b,
    output g,
    output p
);

assign g = a & b;
assign p = a ^ b;

endmodule