// alu_decoder.sv - maps instruction fields to alu_sel
// Two-level decode: alu_op (coarse) → funct3/funct7 (fine)
// Purely combinational - no clock

module alu_decoder (
    input  logic [1:0] alu_op,      // from main control unit
    input  logic [2:0] funct3,      // instr[14:12]
    input  logic       funct7_5,    // instr[30] - distinguishes ADD/SUB, SRL/SRA
    input  logic       op_bit5,     // instr[5]  - 1=R-type, 0=I-type
    output logic [3:0] alu_sel
);

    // reuse the same encoding defined in alu.sv
    localparam ALU_ADD  = 4'b0000;
    localparam ALU_SUB  = 4'b0001;
    localparam ALU_AND  = 4'b0010;
    localparam ALU_OR   = 4'b0011;
    localparam ALU_XOR  = 4'b0100;
    localparam ALU_SLT  = 4'b0101;
    localparam ALU_SLTU = 4'b0110;
    localparam ALU_SLL  = 4'b0111;
    localparam ALU_SRL  = 4'b1000;
    localparam ALU_SRA  = 4'b1001;
    localparam ALU_PASB = 4'b1010;

    always_comb begin
        case (alu_op)

            // ── loads, stores, AUIPC ──────────────────────────────
            // address = rs1 + imm, always addition, no need to check funct fields
            2'b00: alu_sel = ALU_ADD;

            // ── branches ─────────────────────────────────────────
            // BEQ/BNE/BLT/BGE all subtract rs1-rs2
            // zero flag → BEQ/BNE, result sign → BLT/BGE
            // branch comparator logic lives in ex_stage, not here
            2'b01: alu_sel = ALU_SUB;

            // ── LUI ──────────────────────────────────────────────
            // LUI loads a 20-bit immediate into upper bits
            // ALU just passes the immediate (already shifted by imm_gen)
            2'b11: alu_sel = ALU_PASB;

            // ── R-type and I-type ALU ops ─────────────────────────
            // funct3 selects the operation family
            // funct7_5 and op_bit5 together disambiguate within a family
            2'b10: begin
                case (funct3)

                    3'b000: begin
                        // ADD vs SUB
                        // SUB only exists in R-type (op_bit5=1)
                        // For I-type ADDI, funct7_5 is part of the immediate
                        // so we must gate on op_bit5 to avoid treating ADDI as SUB
                        if (funct7_5 & op_bit5)
                            alu_sel = ALU_SUB;
                        else
                            alu_sel = ALU_ADD;
                    end

                    3'b001: alu_sel = ALU_SLL;

                    3'b010: alu_sel = ALU_SLT;

                    3'b011: alu_sel = ALU_SLTU;

                    3'b100: alu_sel = ALU_XOR;

                    3'b101: begin
                        // SRL vs SRA - funct7[5] distinguishes
                        // this works for both R-type SRLI/SRAI
                        // and I-type SRLI/SRAI because the spec
                        // uses instr[30] identically for both
                        if (funct7_5)
                            alu_sel = ALU_SRA;
                        else
                            alu_sel = ALU_SRL;
                    end

                    3'b110: alu_sel = ALU_OR;

                    3'b111: alu_sel = ALU_AND;

                    default: alu_sel = ALU_ADD;
                endcase
            end

            default: alu_sel = ALU_ADD;
        endcase
    end

endmodule