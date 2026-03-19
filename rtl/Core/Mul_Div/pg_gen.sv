module pg_gen(
    input a,
    input b,
    output g,
    output p
);

assign g = a & b;
assign p = a ^ b;

endmodule