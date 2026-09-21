// alu.sv - RV32I ALU, fully combinational
// All operations needed for base integer ISA
// P2: 5-stage RISC-V CPU

module alu (
    input  logic [31:0] a,          // operand A (rs1 or PC)
    input  logic [31:0] b,          // operand B (rs2 or immediate)
    input  logic [3:0]  alu_sel,    // operation select from alu_decoder
    output logic [31:0] result,     // ALU result
    output logic        zero,       // 1 if result == 0 (used by branch control)
    output logic        overflow    // signed overflow flag
);

    // ALU select encoding - keep in sync with alu_decoder.sv
    localparam ALU_ADD  = 4'b0000;
    localparam ALU_SUB  = 4'b0001;
    localparam ALU_AND  = 4'b0010;
    localparam ALU_OR   = 4'b0011;
    localparam ALU_XOR  = 4'b0100;
    localparam ALU_SLT  = 4'b0101;  // signed
    localparam ALU_SLTU = 4'b0110;  // unsigned
    localparam ALU_SLL  = 4'b0111;
    localparam ALU_SRL  = 4'b1000;
    localparam ALU_SRA  = 4'b1001;
    localparam ALU_PASB = 4'b1010;  // pass B - for LUI

    logic [31:0] sum;
    logic        carry_in;

    // Subtraction reuses the adder: A - B == A + (~B) + 1
    assign carry_in = (alu_sel == ALU_SUB) ? 1'b1 : 1'b0;
    assign sum      = a + (alu_sel == ALU_SUB ? ~b : b) + {31'b0, carry_in};

    always_comb begin
        result = 32'b0;
        case (alu_sel)
            ALU_ADD  : result = sum;
            ALU_SUB  : result = sum;
            ALU_AND  : result = a & b;
            ALU_OR   : result = a | b;
            ALU_XOR  : result = a ^ b;
            ALU_SLT  : result = {31'b0, ($signed(a) < $signed(b))};
            ALU_SLTU : result = {31'b0, (a < b)};
            ALU_SLL  : result = a << b[4:0];   // only low 5 bits used for shift
            ALU_SRL  : result = a >> b[4:0];
            ALU_SRA  : result = $signed(a) >>> b[4:0];
            ALU_PASB : result = b;
            default  : result = 32'b0;
        endcase
    end

    // Zero flag - drives branch resolution in EX/MEM stage
    assign zero = (result == 32'b0);

    // Signed overflow: only valid for ADD/SUB
    // Overflow when operands have same sign but result has different sign
    assign overflow = (alu_sel == ALU_ADD) ?
                        (~a[31] & ~b[31] &  result[31]) |   // pos+pos=neg
                        ( a[31] &  b[31] & ~result[31])     // neg+neg=pos
                    : (alu_sel == ALU_SUB) ?
                        (~a[31] &  b[31] &  result[31]) |   // pos-neg=neg
                        ( a[31] & ~b[31] & ~result[31])     // neg-pos=pos
                    : 1'b0;

endmodule