// ex_stage.sv - execute stage
// Forwarding muxes, ALU, branch resolution, branch target
//
// ================== CHANGE: DEDICATED BRANCH COMPARATOR ==================
//
// WHY (timing):
// branch_condition used to be derived from the ALU's outputs:
//     zero      = (result == 0)      -- a 32-input reduction OF the result
//     overflow  = f(a, b, result)
//     alu_result[31]
// so the branch decision could not start until the ALU had produced its
// full 32-bit result AND the output mux had selected it. That put the
// entire ALU, the result mux, and a 32-bit OR-reduce in series ahead of
// branch_taken, which then feeds straight back into ID/EX.
//
// Measured on the P4 design (7z020, 100 MHz) that path was:
//     id_ex_rs1 -> ALU carry chain -> alu_a -> ex_mem_alu_result
//       -> overflow -> zero -> branch_condition -> ex_mem_branch_taken
//       -> id_ex_pc
//     14 logic levels, 11.873 ns, WNS -2.129 ns
//
// The comparator below computes eq / lt / ltu DIRECTLY from the forwarded
// operands, in parallel with the ALU rather than after it. A comparison
// is one subtract-and-test-sign, so it is a single carry chain instead of
// adder + mux + reduction.
//
// WHY (correctness) -- this also fixes a real bug:
// the old decode used the SIGNED overflow flag for the UNSIGNED branches:
//     3'b110: branch_condition = ~zero & ~overflow;   // BLTU
//     3'b111: branch_condition =  zero |  overflow;   // BGEU
// overflow is signed overflow, so BLTU/BGEU gave wrong answers for
// operand pairs that differ in their MSB. The existing testbenches never
// caught it because the bubble-sort program only uses blt (signed).
// The comparator computes the unsigned comparison properly.
//
// alu.sv is left UNCHANGED. Its zero/overflow outputs simply stop being
// used for branches; synthesis prunes whatever becomes dead.

module ex_stage (
    // data from ID/EX register
    input  logic [31:0] pc,
    input  logic [31:0] rs1_data,
    input  logic [31:0] rs2_data,
    input  logic [31:0] imm,
    input  logic [4:0]  rs1, rs2, rd,
    // control signals from ID/EX register
    input  logic        alu_src,
    input  logic [1:0]  alu_op,
    input  logic        branch,
    input  logic        jump,
    input  logic [2:0]  funct3,
    input  logic        funct7_5,
    input  logic [6:0]  opcode,
    // forwarding inputs
    input  logic [1:0]  forwardA,       // from forwarding unit
    input  logic [1:0]  forwardB,       // from forwarding unit
    input  logic [31:0] ex_mem_result,  // EX/MEM alu result
    input  logic [31:0] mem_wb_data,    // MEM/WB writeback data
    // outputs → EX/MEM register
    output logic [31:0] alu_result,
    output logic [31:0] rs2_out,        // forwarded rs2 - needed for stores
    output logic        branch_taken,
    output logic [31:0] branch_target
);

    // ── forwarding mux A ─────────────────────────────────────────
    logic [31:0] fwd_a;
    always_comb begin
        case (forwardA)
            2'b10:   fwd_a = ex_mem_result;
            2'b01:   fwd_a = mem_wb_data;
            default: fwd_a = rs1_data;
        endcase
    end

    // ── forwarding mux B ─────────────────────────────────────────
    logic [31:0] fwd_b;
    always_comb begin
        case (forwardB)
            2'b10:   fwd_b = ex_mem_result;
            2'b01:   fwd_b = mem_wb_data;
            default: fwd_b = rs2_data;
        endcase
    end

    // rs2_out carries the forwarded rs2 value to EX/MEM
    // stores need this - the ALU computes the address, not the store data
    assign rs2_out = fwd_b;

    // ── AUIPC: select PC as ALU A input ──────────────────────────
    logic [31:0] alu_a;
    assign alu_a = (opcode == 7'b0010111) ? pc : fwd_a;

    // ── ALU B input mux ──────────────────────────────────────────
    // alu_src=1 → immediate, alu_src=0 → forwarded rs2
    logic [31:0] alu_b;
    assign alu_b = alu_src ? imm : fwd_b;

    // ── alu_decoder ───────────────────────────────────────────────
    logic [3:0] alu_sel;
    alu_decoder u_alu_decoder (
        .alu_op   (alu_op),
        .funct3   (funct3),
        .funct7_5 (funct7_5),
        .op_bit5  (opcode[5]),
        .alu_sel  (alu_sel)
    );

    // ── ALU ───────────────────────────────────────────────────────
    // zero/overflow are still produced by the ALU but are no longer used
    // for branch resolution (see header). Left connected so alu.sv needs
    // no change; synthesis prunes the now-dead logic.
    logic        zero, overflow;
    /* verilator lint_off UNUSED */
    alu u_alu (
        .a        (alu_a),
        .b        (alu_b),
        .alu_sel  (alu_sel),
        .result   (alu_result),
        .zero     (zero),
        .overflow (overflow)
    );
    /* verilator lint_on UNUSED */

    // ── branch target ─────────────────────────────────────────────
    // all branches and JAL: PC + imm
    // JALR: rs1 + imm (use alu_result directly - ALU already computed it)
    assign branch_target = (opcode == 7'b1100111) ?
                            {alu_result[31:1], 1'b0} : // JALR - clear bit 0
                            pc + imm;                  // JAL, branches

    // ── dedicated branch comparator ───────────────────────────────
    // Computed straight from the forwarded operands, in parallel with the
    // ALU. Deliberately does NOT use alu_result / zero / overflow -- that
    // dependency was the critical path. See header note.
    //
    // Note these compare fwd_a / fwd_b, not alu_a / alu_b: branches always
    // compare rs1 against rs2, never PC or an immediate, so the AUIPC and
    // alu_src muxes are correctly bypassed here.
    logic cmp_eq, cmp_lt_s, cmp_lt_u;
    assign cmp_eq   = (fwd_a == fwd_b);
    assign cmp_lt_s = ($signed(fwd_a) < $signed(fwd_b));
    assign cmp_lt_u = (fwd_a < fwd_b);

    // ── branch decision ───────────────────────────────────────────
    logic branch_condition;
    always_comb begin
        case (funct3)
            3'b000: branch_condition =  cmp_eq;    // BEQ
            3'b001: branch_condition = ~cmp_eq;    // BNE
            3'b100: branch_condition =  cmp_lt_s;  // BLT
            3'b101: branch_condition = ~cmp_lt_s;  // BGE
            3'b110: branch_condition =  cmp_lt_u;  // BLTU
            3'b111: branch_condition = ~cmp_lt_u;  // BGEU
            default: branch_condition = 1'b0;
        endcase
    end

    // branch taken if instruction is a branch AND condition is true
    // OR if instruction is a jump (always taken)
    assign branch_taken = (branch & branch_condition) | jump;

endmodule