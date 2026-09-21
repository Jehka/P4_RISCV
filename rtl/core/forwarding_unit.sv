// forwarding_unit.sv - EX-EX and MEM-EX forwarding
// Purely combinational
// Priority: EX/MEM > MEM/WB (EX/MEM is newer)

module forwarding_unit (
    // current instruction in EX stage
    input  logic [4:0] id_ex_rs1,
    input  logic [4:0] id_ex_rs2,
    // instruction in MEM stage (one cycle ahead)
    input  logic       ex_mem_reg_write,
    input  logic [4:0] ex_mem_rd,
    // instruction in WB stage (two cycles ahead)
    input  logic       mem_wb_reg_write,
    input  logic [4:0] mem_wb_rd,
    // forwarding select signals → EX stage muxes
    output logic [1:0] forwardA,  // 00=regfile 10=EX/MEM 01=MEM/WB
    output logic [1:0] forwardB
);

    // ── ForwardA ──────────────────────────────────────────────────
    always_comb begin
        if (ex_mem_reg_write &&
            (ex_mem_rd != 5'b0) &&
            (ex_mem_rd == id_ex_rs1))
            forwardA = 2'b10;   // EX-EX forward (newest)

        else if (mem_wb_reg_write &&
                 (mem_wb_rd != 5'b0) &&
                 (mem_wb_rd == id_ex_rs1))
            forwardA = 2'b01;   // MEM-EX forward

        else
            forwardA = 2'b00;   // no forwarding - use regfile value
    end

    // ── ForwardB ──────────────────────────────────────────────────
    always_comb begin
        if (ex_mem_reg_write &&
            (ex_mem_rd != 5'b0) &&
            (ex_mem_rd == id_ex_rs2))
            forwardB = 2'b10;

        else if (mem_wb_reg_write &&
                 (mem_wb_rd != 5'b0) &&
                 (mem_wb_rd == id_ex_rs2))
            forwardB = 2'b01;

        else
            forwardB = 2'b00;
    end

endmodule