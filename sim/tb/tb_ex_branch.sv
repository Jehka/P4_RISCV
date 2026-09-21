// tb_ex_branch.sv
// Focused test of ex_stage's branch resolution.
//
// WHY THIS EXISTS:
// The old branch decode used the SIGNED overflow flag for the UNSIGNED
// branches (BLTU/BGEU). That is wrong whenever the two operands differ in
// their MSB -- exactly the cases where signed and unsigned comparison
// disagree. No existing testbench caught it, because the bubble-sort
// program only ever executes blt (signed).
//
// So this test drives the operand pairs where signed and unsigned
// comparison give OPPOSITE answers, and checks all six branch types
// against a reference computed independently in the testbench.
//
// Combinational only -- ex_stage has no state.

`timescale 1ns/1ps

module tb_ex_branch;

    logic [31:0] pc, rs1_data, rs2_data, imm;
    logic [4:0]  rs1, rs2, rd;
    logic        alu_src, branch, jump;
    logic [1:0]  alu_op, forwardA, forwardB;
    logic [2:0]  funct3;
    logic        funct7_5;
    logic [6:0]  opcode;
    logic [31:0] ex_mem_result, mem_wb_data;

    logic [31:0] alu_result, rs2_out, branch_target;
    logic        branch_taken;

    ex_stage dut (
        .pc(pc), .rs1_data(rs1_data), .rs2_data(rs2_data), .imm(imm),
        .rs1(rs1), .rs2(rs2), .rd(rd),
        .alu_src(alu_src), .alu_op(alu_op), .branch(branch), .jump(jump),
        .funct3(funct3), .funct7_5(funct7_5), .opcode(opcode),
        .forwardA(forwardA), .forwardB(forwardB),
        .ex_mem_result(ex_mem_result), .mem_wb_data(mem_wb_data),
        .alu_result(alu_result), .rs2_out(rs2_out),
        .branch_taken(branch_taken), .branch_target(branch_target)
    );

    int errors = 0;

    // Reference model, computed independently of the DUT.
    function automatic logic expect_taken(input [2:0] f3,
                                          input [31:0] a, input [31:0] b);
        case (f3)
            3'b000: expect_taken = (a == b);                       // BEQ
            3'b001: expect_taken = (a != b);                       // BNE
            3'b100: expect_taken = ($signed(a) <  $signed(b));     // BLT
            3'b101: expect_taken = ($signed(a) >= $signed(b));     // BGE
            3'b110: expect_taken = (a <  b);                       // BLTU
            3'b111: expect_taken = (a >= b);                       // BGEU
            default: expect_taken = 1'b0;
        endcase
    endfunction

    function automatic string bname(input [2:0] f3);
        case (f3)
            3'b000: bname = "BEQ ";
            3'b001: bname = "BNE ";
            3'b100: bname = "BLT ";
            3'b101: bname = "BGE ";
            3'b110: bname = "BLTU";
            3'b111: bname = "BGEU";
            default: bname = "????";
        endcase
    endfunction

    task automatic try(input [2:0] f3, input [31:0] a, input [31:0] b,
                       input string label);
        logic exp;
        begin
            funct3   = f3;
            rs1_data = a;
            rs2_data = b;
            #1;
            exp = expect_taken(f3, a, b);
            if (branch_taken !== exp) begin
                $display("FAIL %s %s: a=%h b=%h got=%b exp=%b",
                         bname(f3), label, a, b, branch_taken, exp);
                errors++;
            end else begin
                $display("PASS %s %s: a=%h b=%h -> %b",
                         bname(f3), label, a, b, branch_taken);
            end
        end
    endtask

    // Operand pairs chosen so signed and unsigned comparison DISAGREE.
    // 0x8000_0000 is the most negative signed value but the largest-ish
    // unsigned value; 0xFFFF_FFFF is -1 signed but max unsigned.
    initial begin
        pc = 32'h1000; imm = 32'h20;
        rs1 = 5'd1; rs2 = 5'd2; rd = 5'd3;
        alu_src = 1'b0; alu_op = 2'b01;
        branch = 1'b1; jump = 1'b0;
        funct7_5 = 1'b0; opcode = 7'b1100011;   // BRANCH opcode
        forwardA = 2'b00; forwardB = 2'b00;     // no forwarding
        ex_mem_result = 32'd0; mem_wb_data = 32'd0;
        #1;

        // ---- equality ----
        try(3'b000, 32'd5, 32'd5, "equal");
        try(3'b000, 32'd5, 32'd6, "not equal");
        try(3'b001, 32'd5, 32'd5, "equal");
        try(3'b001, 32'd5, 32'd6, "not equal");

        // ---- signed, both positive ----
        try(3'b100, 32'd3, 32'd7, "3<7");
        try(3'b100, 32'd7, 32'd3, "7<3");
        try(3'b101, 32'd7, 32'd3, "7>=3");
        try(3'b101, 32'd3, 32'd7, "3>=7");

        // ---- signed, negative operands ----
        try(3'b100, 32'hFFFF_FFFF, 32'd1,          "-1 < 1");
        try(3'b100, 32'd1,          32'hFFFF_FFFF, "1 < -1");
        try(3'b101, 32'hFFFF_FFFF, 32'hFFFF_FFFE,  "-1 >= -2");

        // ---- THE CASES THE OLD CODE GOT WRONG ----
        // signed and unsigned disagree here: as unsigned, 0xFFFFFFFF is
        // the largest value; as signed it is -1.
        try(3'b110, 32'hFFFF_FFFF, 32'd1,          "max_u < 1 (unsigned)");
        try(3'b110, 32'd1,          32'hFFFF_FFFF, "1 < max_u (unsigned)");
        try(3'b111, 32'hFFFF_FFFF, 32'd1,          "max_u >= 1 (unsigned)");
        try(3'b111, 32'd1,          32'hFFFF_FFFF, "1 >= max_u (unsigned)");

        // MSB boundary: 0x8000_0000 is most-negative signed, large unsigned
        try(3'b110, 32'h8000_0000, 32'h7FFF_FFFF, "0x8.. < 0x7F.. (unsigned)");
        try(3'b100, 32'h8000_0000, 32'h7FFF_FFFF, "0x8.. < 0x7F.. (signed)");
        try(3'b111, 32'h8000_0000, 32'h7FFF_FFFF, "0x8.. >= 0x7F.. (unsigned)");
        try(3'b101, 32'h8000_0000, 32'h7FFF_FFFF, "0x8.. >= 0x7F.. (signed)");

        // ---- equal operands on the ordering branches ----
        try(3'b100, 32'd42, 32'd42, "equal");
        try(3'b101, 32'd42, 32'd42, "equal");
        try(3'b110, 32'd42, 32'd42, "equal");
        try(3'b111, 32'd42, 32'd42, "equal");

        // ---- branch=0 must never take, whatever the condition ----
        branch = 1'b0;
        funct3 = 3'b000; rs1_data = 32'd5; rs2_data = 32'd5;
        #1;
        if (branch_taken !== 1'b0) begin
            $display("FAIL branch=0 still taken");
            errors++;
        end else $display("PASS branch=0 not taken");

        // ---- jump=1 must always take ----
        jump = 1'b1;
        funct3 = 3'b000; rs1_data = 32'd5; rs2_data = 32'd9;  // BEQ false
        #1;
        if (branch_taken !== 1'b1) begin
            $display("FAIL jump=1 not taken");
            errors++;
        end else $display("PASS jump=1 always taken");

        $display("=========================");
        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("%0d TEST(S) FAILED", errors);
        $display("=========================");
        $finish;
    end

endmodule : tb_ex_branch