// if_stage.sv - instruction fetch
// Program hardcoded directly - no external hex file needed

module if_stage (
    input  logic        clk, rst,
    input  logic        pc_write,
    input  logic        pc_sel,
    input  logic [31:0] branch_target,
    output logic [31:0] instr,
    output logic [31:0] pc,
    output logic [31:0] pc_plus4
);

    (* rom_style = "block" *) logic [31:0] imem [0:1023];

    initial begin
    imem[0]  = 32'h20000513; // addi a0, x0, 0x200
    imem[1]  = 32'h00A00593; // addi a1, x0, 10
    imem[2]  = 32'h00000293; // addi t0, x0, 0      (i = 0)
    imem[3]  = 32'h00000313; // addi t1, x0, 0      (j = 0)
    imem[4]  = 32'hFFF58F93; // addi t6, a1, -1     (n-1)
    imem[5]  = 32'h405F8FB3; // sub  t6, t6, t0     (n-1-i)
    imem[6]  = 32'h00231393; // slli t2, t1, 2      (j*4)
    imem[7]  = 32'h00750E33; // add  t3, a0, t2     (base + offset)
    imem[8]  = 32'h000E2E83; // lw   t4, 0(t3)      (arr[j])
    imem[9]  = 32'h004E2F03; // lw   t5, 4(t3)      (arr[j+1])
    imem[10] = 32'h01EED463; // bge  t4, t5, +8     (skip swap)
    imem[11] = 32'h00C0006F; // jal  x0, +12        (to no_swap)
    imem[12] = 32'h01EE2023; // sw   t5, 0(t3)      (swap)
    imem[13] = 32'h01DE2223; // sw   t4, 4(t3)      (swap)
    imem[14] = 32'h00130313; // addi t1, t1, 1      (j++)
    imem[15] = 32'hFDF34EE3; // blt  t1, t6, -36    (inner loop)
    imem[16] = 32'h00128293; // addi t0, t0, 1      (i++)
    imem[17] = 32'hFCB2C4E3; // blt  t0, a1, -56    (outer loop)
    imem[18] = 32'h20002503; // lw   a0, 0x200(x0)  (load sorted min)
    imem[19] = 32'h0000006F; // jal  x0, 0          (spin forever) ← FIXED
end

    // ── PC register ───────────────────────────────────────────────
    logic [31:0] pc_reg;
    logic [31:0] next_pc;

    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            pc_reg <= 32'h0000_0000;
        else if (pc_write)
            pc_reg <= next_pc;
    end

    // ── combinational ─────────────────────────────────────────────
    assign pc_plus4 = pc_reg + 32'h4;
    assign next_pc  = pc_sel ? branch_target : pc_plus4;
    assign pc       = pc_reg;
    assign instr    = imem[pc_reg[11:2]];

endmodule