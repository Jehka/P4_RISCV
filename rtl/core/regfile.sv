// regfile.sv - 32x32 register file, RV32I
// Two async read ports, one sync write port, write-first on collision
// x0 hardwired to zero
//
// CHANGE vs the P3 version: x10 (a0) is exposed through a real output
// port instead of being tapped hierarchically from outside.
//
// riscv_cpu_p3.sv line 335 did:
//     assign debug_out = u_id.u_regfile.regs[10];
// A cross-module hierarchical reference into the array blocks LUTRAM
// inference -- synthesis cannot map a memory to distributed RAM when
// something outside reads an arbitrary element of it. Vivado said so
// explicitly:
//     INFO: [Synth 8-6085] Hierarchical reference on 'regs' stops
//                          possible memory inference
// The cost was the whole file built from flip-flops: 1704 LUTs +
// 1024 FFs, plus the wide read muxes that come with it.
//
// Exposing x10 as a port gives the same value with no hierarchical
// reference, so the array can infer as LUTRAM.

module regfile (
    input  logic        clk,
    input  logic        we,
    input  logic [4:0]  rs1, rs2,
    input  logic [4:0]  rd,
    input  logic [31:0] wd,
    output logic [31:0] rd1, rd2,

    // x10 / a0, for debug observability. See header note.
    output logic [31:0] dbg_x10
);

    logic [31:0] regs [31:0];

    // Synchronous write - x0 write is silently ignored
    always_ff @(posedge clk) begin
        if (we && rd != 5'b0)
            regs[rd] <= wd;
    end

    // Async read - write-first forwarding on address match
    assign rd1 = (rs1 == 5'b0)              ? 32'b0 :
                 (we && rd == rs1) ? wd              :
                 regs[rs1];

    assign rd2 = (rs2 == 5'b0)              ? 32'b0 :
                 (we && rd == rs2) ? wd              :
                 regs[rs2];

    // Fixed-index read. Unlike a hierarchical reference this is an
    // ordinary output of the module, so it does not defeat inference.
    assign dbg_x10 = regs[10];

endmodule