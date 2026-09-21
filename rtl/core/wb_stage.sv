// wb_stage.sv - writeback
// Selects between ALU result and memory load data
// Output goes to regfile write port in id_stage

module wb_stage (
    input  logic        mem_to_reg,   // 0=ALU result, 1=memory data
    input  logic [31:0] alu_result,
    input  logic [31:0] mem_data,
    output logic [31:0] wb_data
);
    assign wb_data = mem_to_reg ? mem_data : alu_result;
endmodule