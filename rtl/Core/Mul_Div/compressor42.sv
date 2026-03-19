
module compressor42 #(
    parameter DATA_WIDTH = 32
)(
    input  logic [DATA_WIDTH*2:0] in1,in2,in3,in4,
    input  logic                    cin,
    output logic [DATA_WIDTH*2+1:0] out1,out2,
    output logic                    cout
);
logic   [DATA_WIDTH*2:0]  w1,w2,w3;

assign w1 = in1 ^ in2 ^ in3 ^ in4;
assign w2 = (in1 & in2) | (in3 & in4);
assign w3 = (in1 | in2) & (in3 | in4);

assign out2 = { w1[DATA_WIDTH*2] , w1} ^ {w3 , cin};
assign cout = w3[DATA_WIDTH*2];
//下面代码得到的结果out1的权值高一位，下一层部分积计算时需要将out1的结果左移一位（out1<<1）
assign out1 = ({ w1[DATA_WIDTH*2] , w1} & {w3 , cin}) 
| (( ~{w1[DATA_WIDTH*2], w1}) & { w2[DATA_WIDTH*2] , w2});
endmodule  