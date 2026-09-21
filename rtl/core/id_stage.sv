// id_stage.sv - instruction decode
// Instantiates regfile and imm_gen
// Generates all control signals for the pipeline

module id_stage (
    input  logic        clk, rst,
    // from IF/ID register
    input  logic [31:0] instr,
    input  logic [31:0] pc,
    // from WB stage - written back into regfile this cycle
    input  logic        reg_write_wb,
    input  logic [4:0]  rd_wb,
    input  logic [31:0] wd_wb,
    // control signals → ID/EX register
    output logic        reg_write,
    output logic        mem_to_reg,
    output logic        mem_read,
    output logic        mem_write,
    output logic        branch,
    output logic        alu_src,
    output logic [1:0]  alu_op,
    output logic        jump,
    // data → ID/EX register
    output logic [31:0] rd1, rd2,
    output logic [31:0] imm,
    output logic [4:0]  rs1, rs2, rd,

    // x10 / a0 passed up from the register file for debug observability.
    // Replaces the hierarchical reference riscv_cpu_p3 used, which was
    // blocking LUTRAM inference on the regfile array.
    output logic [31:0] dbg_x10
);

    // ── instruction field extraction ──────────────────────────────
    logic [6:0] opcode;
    logic [2:0] funct3;
    logic [6:0] funct7;

    assign opcode = instr[6:0];
    assign funct3 = instr[14:12];
    assign funct7 = instr[31:25];
    assign rs1    = instr[19:15];
    assign rs2    = instr[24:20];
    assign rd     = instr[11:7];

    // ── submodule: register file ──────────────────────────────────
    regfile u_regfile (
        .clk  (clk),
        .we   (reg_write_wb),
        .rs1  (rs1),
        .rs2  (rs2),
        .rd   (rd_wb),
        .wd   (wd_wb),
        .rd1  (rd1),
        .rd2  (rd2),
        .dbg_x10 (dbg_x10)
    );

    // ── submodule: immediate generator ───────────────────────────
    imm_gen u_imm_gen (
        .instr   (instr),
        .imm_out (imm)
    );

    // ── control unit ─────────────────────────────────────────────
    // purely combinational - opcode drives all control signals
    always_comb begin
        // safe defaults - NOP behavior
        reg_write  = 1'b0;
        mem_to_reg = 1'b0;
        mem_read   = 1'b0;
        mem_write  = 1'b0;
        branch     = 1'b0;
        alu_src    = 1'b0;
        alu_op     = 2'b00;
        jump       = 1'b0;

        case (opcode)
            // R-type: ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, SLT, SLTU
            7'b0110011: begin
                reg_write  = 1'b1;
                alu_op     = 2'b10;
            end

            // I-type ALU: ADDI, SLTI, SLTIU, ANDI, ORI, XORI, SLLI, SRLI, SRAI
            7'b0010011: begin
                reg_write  = 1'b1;
                alu_src    = 1'b1;  // B operand = immediate
                alu_op     = 2'b10;
            end

            // Load: LW, LH, LB, LHU, LBU
            7'b0000011: begin
                reg_write  = 1'b1;
                mem_to_reg = 1'b1;  // WB mux selects memory data
                mem_read   = 1'b1;
                alu_src    = 1'b1;  // address = rs1 + imm
                alu_op     = 2'b00; // always ADD
            end

            // Store: SW, SH, SB
            7'b0100011: begin
                mem_write  = 1'b1;
                alu_src    = 1'b1;  // address = rs1 + imm
                alu_op     = 2'b00; // always ADD
            end

            // Branch: BEQ, BNE, BLT, BGE, BLTU, BGEU
            7'b1100011: begin
                branch     = 1'b1;
                alu_op     = 2'b01; // always SUB - zero/sign flags drive branch
            end

            // LUI
            7'b0110111: begin
                reg_write  = 1'b1;
                alu_src    = 1'b1;
                alu_op     = 2'b11; // pass B (immediate) through ALU
            end

            // AUIPC
            7'b0010111: begin
                reg_write  = 1'b1;
                alu_src    = 1'b1;
                alu_op     = 2'b00; // ADD - result = PC + imm
            end

            // JAL
            7'b1101111: begin
                reg_write  = 1'b1;  // rd = PC+4 (return address)
                jump       = 1'b1;
                alu_op     = 2'b00;
            end

            // JALR
            7'b1100111: begin
                reg_write  = 1'b1;  // rd = PC+4
                alu_src    = 1'b1;  // target = rs1 + imm
                jump       = 1'b1;
                alu_op     = 2'b00;
            end

            default: begin
                // NOP - all signals already defaulted to 0
            end
        endcase
    end

endmodule