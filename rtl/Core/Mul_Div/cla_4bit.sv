module cla_4bit (
    input   [3:0]   op1,
    input   [3:0]   op2,
    input           cin,
    output  [3:0]   sum,
    output          cout
);


logic [3:0] g;
logic [3:0] p;
logic [4:0] c_4bit;

pg_gen u_gen_0 (.a( op1[0]),.b( op2[0]),.g( g[0]  ),.p( p[0]  ));
pg_gen u_gen_1 (.a( op1[1]),.b( op2[1]),.g( g[1]  ),.p( p[1]  ));
pg_gen u_gen_2 (.a( op1[2]),.b( op2[2]),.g( g[2]  ),.p( p[2]  ));
pg_gen u_gen_3 (.a( op1[3]),.b( op2[3]),.g( g[3]  ),.p( p[3]  ));

assign c_4bit[0] = cin;
assign c_4bit[1] = g[0] + ( c_4bit[0] & p[0] );
assign c_4bit[2] = g[1] + ( (g[0] + ( c_4bit[0] & p[0]) ) & p[1] );
assign c_4bit[3] = g[2] + ( (g[1] + ( (g[0] + (c_4bit[0] & p[0]) ) & p[1])) & p[2] );
assign c_4bit[4] = g[3] + ( (g[2] + ( (g[1] + ( (g[0] + (c_4bit[0] & p[0]) ) & p[1])) & p[2] )) & p[3]);
assign cout = c_4bit[4];

assign sum[0] = p[0] ^ c_4bit[0];
assign sum[1] = p[1] ^ c_4bit[1];
assign sum[2] = p[2] ^ c_4bit[2];
assign sum[3] = p[3] ^ c_4bit[3];
endmodule