// ============================================================
// 模块名称：CompareTree
// 功能：非递归流水线比较树，查找数组最大值及其最小索引
// 特点：
//   - 使用 generate for 循环按层级迭代，避免递归例化
//   - 每层仅分配实际需要的节点资源，无预分配浪费
//   - 支持有符号/无符号比较，相等时返回最小索引
// 参数说明：
//   - DATA_WIDTH   : 每个输入数据的位宽(默认16位)
//   - DATA_NUM     : 输入数据个数(默认8个)
//   - SIGNED       : 1=有符号数比较, 0=无符号数比较 (默认1)
// ============================================================

module CompareTree #(
    parameter int DATA_WIDTH   = 16,
    parameter int DATA_NUM     = 16,
    parameter int SIGNED       = 1,
    localparam int MAX_LEVEL = $clog2(DATA_NUM),
    localparam int INDEX_WIDTH = $clog2(DATA_NUM)
)(
    input  logic [DATA_WIDTH*DATA_NUM-1:0]   input_data,  // {d[DATA_NUM-1], ..., d[0]}
    output logic [DATA_WIDTH-1:0]            out_max,
    output logic [INDEX_WIDTH-1:0]           max_index
);

initial begin
    if ((DATA_NUM & (DATA_NUM - 1)) != 0) begin
        $error("CompareTree: DATA_NUM must be power of 2, got %0d", DATA_NUM);
    end
end

generate
    genvar level, idx;
    for(level = 0; level < MAX_LEVEL; level++) begin : tree_level_gen
        localparam COMPARATOR_NUM = DATA_NUM >> (level+1);
        logic [DATA_WIDTH-1:0] cmp_pipe_out [0:COMPARATOR_NUM-1];
        logic [INDEX_WIDTH-1:0] cmp_pipe_idx [0:COMPARATOR_NUM-1];
        for(idx = 0; idx < COMPARATOR_NUM; idx++) begin : tree_inst_gen
            if (level == 0) begin
                if (SIGNED) begin
                    assign cmp_pipe_out[idx] = $signed(input_data[2*idx*DATA_WIDTH +: DATA_WIDTH]) >= $signed(input_data[(2*idx+1)*DATA_WIDTH +: DATA_WIDTH])
                        ? input_data[2*idx*DATA_WIDTH +: DATA_WIDTH] : input_data[(2*idx+1)*DATA_WIDTH +: DATA_WIDTH];
                    assign cmp_pipe_idx[idx] = $signed(input_data[2*idx*DATA_WIDTH +: DATA_WIDTH]) >= $signed(input_data[(2*idx+1)*DATA_WIDTH +: DATA_WIDTH])
                        ? INDEX_WIDTH'(2*idx) : INDEX_WIDTH'(2*idx+1);
                end else begin
                    assign cmp_pipe_out[idx] = input_data[2*idx*DATA_WIDTH +: DATA_WIDTH] >= input_data[(2*idx+1)*DATA_WIDTH +: DATA_WIDTH]
                        ? input_data[2*idx*DATA_WIDTH +: DATA_WIDTH] : input_data[(2*idx+1)*DATA_WIDTH +: DATA_WIDTH];
                    assign cmp_pipe_idx[idx] = input_data[2*idx*DATA_WIDTH +: DATA_WIDTH] >= input_data[(2*idx+1)*DATA_WIDTH +: DATA_WIDTH]
                        ? INDEX_WIDTH'(2*idx) : INDEX_WIDTH'(2*idx+1);
                end
            end else begin
                if (SIGNED) begin
                    assign cmp_pipe_out[idx] = $signed(tree_level_gen[level-1].cmp_pipe_out[2*idx]) >= $signed(tree_level_gen[level-1].cmp_pipe_out[2*idx+1])
                        ? tree_level_gen[level-1].cmp_pipe_out[2*idx] : tree_level_gen[level-1].cmp_pipe_out[2*idx+1];
                    assign cmp_pipe_idx[idx] = $signed(tree_level_gen[level-1].cmp_pipe_out[2*idx]) >= $signed(tree_level_gen[level-1].cmp_pipe_out[2*idx+1])
                        ? tree_level_gen[level-1].cmp_pipe_idx[2*idx] : tree_level_gen[level-1].cmp_pipe_idx[2*idx+1];
                end else begin
                    assign cmp_pipe_out[idx] = tree_level_gen[level-1].cmp_pipe_out[2*idx] >= tree_level_gen[level-1].cmp_pipe_out[2*idx+1]
                        ? tree_level_gen[level-1].cmp_pipe_out[2*idx] : tree_level_gen[level-1].cmp_pipe_out[2*idx+1];
                    assign cmp_pipe_idx[idx] = tree_level_gen[level-1].cmp_pipe_out[2*idx] >= tree_level_gen[level-1].cmp_pipe_out[2*idx+1]
                        ? tree_level_gen[level-1].cmp_pipe_idx[2*idx] : tree_level_gen[level-1].cmp_pipe_idx[2*idx+1];
                end
            end
        end
    end
endgenerate

assign out_max = tree_level_gen[MAX_LEVEL-1].cmp_pipe_out[0];
assign max_index = tree_level_gen[MAX_LEVEL-1].cmp_pipe_idx[0];

endmodule