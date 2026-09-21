// imm_gen.sv - immediate generator for all 5 RV32I formats
// Sign extension is always from bit 31 of the instruction

module imm_gen (
    input  logic [31:0] instr,
    output logic [31:0] imm_out
);

    logic [6:0] opcode;
    assign opcode = instr[6:0];

    always_comb begin
        case (opcode)

            // I-type: ADDI, SLTI, ORI, ANDI, XORI, SLLI, SRLI, SRAI
            //         LW, LH, LB, LHU, LBU
            //         JALR
            7'b0010011,     // alu-immediate
            7'b0000011,     // load
            7'b1100111:     // JALR
                imm_out = {{20{instr[31]}}, instr[31:20]};

            // S-type: SW, SH, SB
            // imm[11:5] = instr[31:25]
            // imm[4:0]  = instr[11:7]
            7'b0100011:
                imm_out = {{20{instr[31]}}, instr[31:25], instr[11:7]};

            // B-type: BEQ, BNE, BLT, BGE, BLTU, BGEU
            // imm[12]   = instr[31]
            // imm[11]   = instr[7]
            // imm[10:5] = instr[30:25]
            // imm[4:1]  = instr[11:8]
            // imm[0]    = 0  (always - branches are 2-byte aligned)
            7'b1100011:
                imm_out = {{19{instr[31]}}, instr[31], instr[7],
                           instr[30:25], instr[11:8], 1'b0};

            // U-type: LUI, AUIPC
            // imm[31:12] = instr[31:12]
            // imm[11:0]  = 0
            7'b0110111,     // LUI
            7'b0010111:     // AUIPC
                imm_out = {instr[31:12], 12'b0};

            // J-type: JAL
            // imm[20]    = instr[31]
            // imm[19:12] = instr[19:12]
            // imm[11]    = instr[20]
            // imm[10:1]  = instr[30:21]
            // imm[0]     = 0  (always - jumps are 2-byte aligned)
            7'b1101111:
                imm_out = {{11{instr[31]}}, instr[31], instr[19:12],
                           instr[20], instr[30:21], 1'b0};

            default:
                imm_out = 32'b0;
        endcase
    end

endmodule